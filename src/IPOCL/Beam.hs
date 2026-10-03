-- | Layered beam search over partial plans (ticket 26). Incomplete: a pruned
-- Story is lost, so an empty layer ends the stream with 'GaveUp' (ADR-0007).
module IPOCL.Beam
  ( beamSearch
  ) where

import Data.List (foldl')
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word64)
import IPOCL.Plan
import IPOCL.Refine
import IPOCL.Search
import IPOCL.Signature (dedupeBy)

data Node = Node
  { nId :: !Int
  , nParent :: !(Maybe Int)
  , nReason :: !Text
  , nPlan :: !Plan
  }

-- | The next layer, ranked by priority, seeded tie-break and node number.
type Beam = Map (Double, Word64, Int) Node

-- | Keep the best @width@ plans of each layer by 'planPriority'.
beamSearch :: Int -> Env -> SearchConfig -> Plan -> [SearchEvent]
beamSearch width env cfg root = layer 0 [Node 0 Nothing "initial plan" root] 1 rootSeen
  where
    rootSeen = maybe Set.empty (\sig -> Set.singleton (sig root)) (scSignature cfg)
    layer _ [] _ _ = [GaveUp]
    layer d nodes next seen = visit d nodes Map.empty next seen
    visit d [] beam next seen = layer (d + 1) (Map.elems beam) next seen
    visit d (node : rest) beam next seen =
      let i = nId node
          p = nPlan node
          visited = Visited i (nParent node) (layerReason d (nReason node))
       in case expand env p of
            Solution -> visited Nothing False 0 p : FoundSolution i p : visit d rest beam next seen
            DeadEnd f -> visited f True 0 p : visit d rest beam next seen
            Refined f cs ->
              let (kids, seen') = dedupe seen cs
                  beam' = foldl' (offer (d + 1) i) beam (zip [next ..] kids)
               in visited (Just f) False (length cs) p : visit d rest beam' (next + length kids) seen'
    offer :: Int -> Int -> Beam -> (Int, Child) -> Beam
    offer d parent beam (j, c) = case planPriority cfg d (childPlan c) of
      Nothing -> beam
      Just f -> cap (Map.insert (f, tieBreak cfg j, j) (Node j (Just parent) (childReason c) (childPlan c)) beam)
    -- Capping on every insert bounds memory by the width, not the layer's children.
    cap beam
      | Map.size beam > width = Map.deleteMax beam
      | otherwise = beam
    dedupe seen cs = case scSignature cfg of
      Nothing -> (cs, seen)
      Just sig -> dedupeBy (sig . childPlan) seen cs

layerReason :: Int -> Text -> Text
layerReason d reason = "layer " <> T.pack (show d) <> ": " <> reason
