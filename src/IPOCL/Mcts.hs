-- | Monte Carlo tree search (UCT) over partial plans (ticket 27): varied
-- Stories and anytime behaviour rather than optimal ones.
module IPOCL.Mcts
  ( mctsSearch
  ) where

import Data.Bits (shiftR)
import Data.IntMap.Strict qualified as IM
import Data.List (maximumBy, minimumBy, sortOn)
import Data.Maybe (isNothing)
import Data.Ord (comparing)
import Data.Text (Text)
import Data.Word (Word64)
import IPOCL.Plan
import IPOCL.Refine
import IPOCL.Search

-- | SplitMix64 state.
newtype Gen = Gen Word64

seedGen :: Int -> Gen
seedGen = Gen . mix64 . fromIntegral

nextWord :: Gen -> (Word64, Gen)
nextWord (Gen s) = let s' = s + 0x9e3779b97f4a7c15 in (mix64 s', Gen s')

-- | Uniform in @[0, 1)@.
nextDouble :: Gen -> (Double, Gen)
nextDouble g = let (w, g') = nextWord g in (fromIntegral (w `shiftR` 11) / 9007199254740992, g')

nextBelow :: Int -> Gen -> (Int, Gen)
nextBelow n g = let (w, g') = nextWord g in (fromIntegral (w `mod` fromIntegral n), g')

shuffle :: Gen -> [a] -> ([a], Gen)
shuffle g xs = let (keyed, g') = foldr draw ([], g) xs in (map snd (sortOn fst keyed), g')
  where
    draw x (acc, h) = let (w, h') = nextWord h in ((w, x) : acc, h')

data Status
  = Fresh !Plan
  | Open ![Int]
  | Done

data TreeNode = TreeNode
  { tnDepth :: !Int
  , tnParent :: !(Maybe Int)
  , tnReason :: !Text
  , tnVisits :: !Int
  , tnValue :: !Double
  , tnStatus :: !Status
  }

data Tree = Tree
  { trNodes :: !(IM.IntMap TreeNode)
  , trNext :: !Int
  -- ^ The next node number, shared by tree nodes and rollout steps.
  , trGen :: !Gen
  }

data Ctx = Ctx
  { cxParams :: !MctsParams
  , cxEnv :: !Env
  , cxCfg :: !SearchConfig
  }

-- | A child that is not hopeless, with its best-first priority.
data Scored = Scored {scPriority :: !Double, scChild :: !Child}

-- | The rollout's position: the plan last expanded and its scored children.
data Walk = Walk
  { wNode :: !Int
  , wDepth :: !Int
  , wPlan :: !Plan
  , wKids :: ![Scored]
  , wSteps :: !Int
  }

-- | Search until the root is exhausted; the stream ends only there.
mctsSearch :: MctsParams -> Env -> SearchConfig -> Plan -> [SearchEvent]
mctsSearch params env cfg root
  | isNothing (scHeuristic cfg root) = []
  | otherwise = iterations (Ctx params env cfg) (Tree (IM.singleton 0 (newNode 0 Nothing "initial plan" root)) 1 (seedGen (scSeed cfg)))

newNode :: Int -> Maybe Int -> Text -> Plan -> TreeNode
newNode d parent reason p = TreeNode d parent reason 0 0 (Fresh p)

isDone :: TreeNode -> Bool
isDone n = case tnStatus n of
  Done -> True
  _ -> False

iterations :: Ctx -> Tree -> [SearchEvent]
iterations ctx tree
  | isDone (trNodes tree IM.! 0) = []
  | otherwise = let (evs, tree') = select ctx tree 0 [] in evs ++ iterations ctx tree'

-- | Descend by UCB1 to a node never selected, then expand and roll out from
-- it. The path is kept leaf first.
select :: Ctx -> Tree -> Int -> [Int] -> ([SearchEvent], Tree)
select ctx tree i path = case tnStatus n of
  Fresh p -> grow ctx tree i n p (i : path)
  Open kids -> select ctx tree (pick (mctsExploration (cxParams ctx)) (trNodes tree) n kids) (i : path)
  Done -> error "mctsSearch: selected an exhausted node"
  where
    n = trNodes tree IM.! i

-- | Unvisited children first, in their shuffled order, then the best UCB1.
pick :: Double -> IM.IntMap TreeNode -> TreeNode -> [Int] -> Int
pick c nodes parent kids = case [k | k <- live, tnVisits (nodes IM.! k) == 0] of
  k : _ -> k
  [] -> maximumBy (comparing ucb) live
  where
    live = filter (not . isDone . (nodes IM.!)) kids
    ucb k =
      let child = nodes IM.! k
          visits = fromIntegral (tnVisits child)
       in tnValue child / visits + c * sqrt (log (fromIntegral (tnVisits parent)) / visits)

-- | Expand a freshly selected node, add its children, roll out, back up.
grow :: Ctx -> Tree -> Int -> TreeNode -> Plan -> [Int] -> ([SearchEvent], Tree)
grow ctx tree i n p path = case expand (cxEnv ctx) p of
  Solution -> (visited Nothing False 0 : [FoundSolution i p], settle 1 (finished tree))
  DeadEnd f -> ([visited f True 0], settle 0 (finished tree))
  Refined f cs ->
    let kids = scored ctx (tnDepth n + 1) cs
        (order, g) = shuffle (trGen tree) kids
        ids = take (length order) [trNext tree ..]
        nodes = foldl' (\acc (j, s) -> IM.insert j (newNode (tnDepth n + 1) (Just i) (childReason (scChild s)) (childPlan (scChild s))) acc) (trNodes tree) (zip ids order)
        status = if null ids then Done else Open ids
        tree' = Tree (IM.insert i n {tnStatus = status} nodes) (trNext tree + length ids) g
        (evs, r, g', next) = rollout ctx (trGen tree') (trNext tree') (Walk i (tnDepth n) p kids 0)
     in (visited (Just f) False (length cs) : evs, settle r tree' {trNext = next, trGen = g'})
  where
    visited f dead k = Visited i (tnParent n) (tnReason n) f dead k p
    finished t = t {trNodes = IM.insert i n {tnStatus = Done} (trNodes t)}
    settle r t = t {trNodes = backprop r path (trNodes t)}

scored :: Ctx -> Int -> [Child] -> [Scored]
scored ctx d cs = [Scored f c | c <- cs, Just f <- [planPriority (cxCfg ctx) d (childPlan c)]]

-- | Add the reward along the path, leaf first, marking a node exhausted once
-- all of its children are.
backprop :: Double -> [Int] -> IM.IntMap TreeNode -> IM.IntMap TreeNode
backprop r path nodes0 = foldl' step nodes0 path
  where
    step nodes i = IM.adjust (exhaust nodes . credit) i nodes
    credit n = n {tnVisits = tnVisits n + 1, tnValue = tnValue n + r}
    exhaust nodes n = case tnStatus n of
      Open kids | all (isDone . (nodes IM.!)) kids -> n {tnStatus = Done}
      _ -> n

-- | Descend without adding nodes, returning the steps, the reward, and the
-- generator and node number after it.
rollout :: Ctx -> Gen -> Int -> Walk -> ([SearchEvent], Double, Gen, Int)
rollout ctx g next w
  | null (wKids w) = ([], 0, g, next)
  | wSteps w >= mctsRolloutDepth (cxParams ctx) = ([], cutOff (cxCfg ctx) (wPlan w), g, next)
  | otherwise = case expand (cxEnv ctx) p of
      Solution -> (step Nothing False 0 : [FoundSolution next p], 1, g', next + 1)
      DeadEnd f -> ([step f True 0], 0, g', next + 1)
      Refined f cs ->
        let (evs, r, g'', next') = rollout ctx g' (next + 1) (Walk next d p (scored ctx (d + 1) cs) (wSteps w + 1))
         in (step (Just f) False (length cs) : evs, r, g'', next')
  where
    (Scored _ c, g') = policy g (wKids w)
    p = childPlan c
    d = wDepth w + 1
    step f dead k = Visited next (Just (wNode w)) ("rollout: " <> childReason c) f dead k p

cutOff :: SearchConfig -> Plan -> Double
cutOff cfg p = maybe 0 (\h -> 1 / (1 + fromIntegral h)) (scHeuristic cfg p)

-- | Epsilon-greedy: usually the lowest priority, otherwise uniformly random.
policy :: Gen -> [Scored] -> (Scored, Gen)
policy g kids
  | u < 0.8 = (minimumBy (comparing scPriority) kids, g')
  | otherwise = let (k, g'') = nextBelow (length kids) g' in (kids !! k, g'')
  where
    (u, g') = nextDouble g
