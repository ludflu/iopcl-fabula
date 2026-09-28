-- | Best-first search over plans, as a lazy stream of events so callers can
-- impose limits, time-outs and tracing without the search knowing about them.
module IPOCL.Search
  ( SearchConfig (..)
  , defaultSearchConfig
  , SearchEvent (..)
  , search
  , mix64
  ) where

import Data.Bits (xor)
import Data.IntMap.Strict qualified as IM
import Data.Set qualified as Set
import Data.Text (Text)
import IPOCL.Plan
import IPOCL.Refine
import IPOCL.Signature (PlanSignature, dedupeBy, mix64)

data SearchConfig = SearchConfig
  { scWeight :: !Double
  , scGreedy :: !Bool
  , scSeed :: !Int
  , scCost :: Int -> Plan -> Int
  -- ^ @g@: cost of the plan so far, given its depth in the search tree.
  , scHeuristic :: Plan -> Maybe Int
  -- ^ @h@: estimated remaining cost; 'Nothing' marks a plan as hopeless.
  , scSignature :: Maybe (Plan -> PlanSignature)
  -- ^ When set, plans whose signature was already generated are dropped.
  }

defaultSearchConfig :: SearchConfig
defaultSearchConfig =
  SearchConfig
    { scWeight = 1
    , scGreedy = False
    , scSeed = 0
    , scCost = \_ p -> length (actionSteps p) + IM.size (planFrames p)
    , scHeuristic = \p -> Just (length (planOpenConds p) + length (planPendingIntent p))
    , scSignature = Nothing
    }

data SearchEvent
  = Visited
      { evNode :: !Int
      , evParent :: !(Maybe Int)
      , evReason :: !Text
      , evFlaw :: !(Maybe Flaw)
      , evDeadEnd :: !Bool
      , evChildren :: !Int
      , evPlan :: !Plan
      }
  | FoundSolution {evNode :: !Int, evPlan :: !Plan}

data Node = Node
  { nDepth :: !Int
  , nParent :: !(Maybe Int)
  , nReason :: !Text
  , nPlan :: !Plan
  }

-- | Explore until the frontier is exhausted; the stream ends there.
search :: Env -> SearchConfig -> Plan -> [SearchEvent]
search env cfg root = go (maybe Set.empty Set.singleton (key 0 0 root)) (IM.singleton 0 (Node 0 Nothing "initial plan" root)) 1 seen0
  where
    seen0 = maybe Set.empty (\sig -> Set.singleton (sig root)) (scSignature cfg)
    key d i p = case priority d p of
      Just f -> Just (f, mix64 (fromIntegral (scSeed cfg) `xor` fromIntegral i), i)
      Nothing -> Nothing
    priority d p = do
      h <- scHeuristic cfg p
      let g = if scGreedy cfg then 0 else fromIntegral (scCost cfg d p)
      Just (g + scWeight cfg * fromIntegral h :: Double)
    go frontier nodes next seen = case Set.minView frontier of
      Nothing -> []
      Just ((_, _, i), rest) ->
        let node = nodes IM.! i
            nodes' = IM.delete i nodes
            p = nPlan node
         in case expand env p of
              Solution ->
                Visited i (nParent node) (nReason node) Nothing False 0 p
                  : FoundSolution i p
                  : go rest nodes' next seen
              DeadEnd f -> Visited i (nParent node) (nReason node) f True 0 p : go rest nodes' next seen
              Refined f cs ->
                let (kids, seen') = dedupe seen cs
                    numbered = zip [next ..] kids
                    frontier' = foldr (\(j, c) acc -> maybe acc (`Set.insert` acc) (key (nDepth node + 1) j (childPlan c))) rest numbered
                    nodes'' = foldr (\(j, c) acc -> IM.insert j (Node (nDepth node + 1) (Just i) (childReason c) (childPlan c)) acc) nodes' numbered
                 in Visited i (nParent node) (nReason node) (Just f) False (length cs) p
                      : go frontier' nodes'' (next + length kids) seen'
    dedupe seen cs = case scSignature cfg of
      Nothing -> (cs, seen)
      Just sig -> dedupeBy (sig . childPlan) seen cs
