-- | Total orders consistent with a plan's partial order.
module IPOCL.Linearize
  ( linearize
  ) where

import Data.IntMap.Strict qualified as IM
import Data.IntSet qualified as IS
import Data.List (minimumBy)
import Data.Ord (comparing)
import IPOCL.Order
import IPOCL.Plan

-- | A deterministic topological order, init first and goal last. Among ready
-- Steps, Motivating steps come first, then Steps that must precede one, so
-- intentions are told as early as possible and before they are acted on.
linearize :: Plan -> [Step]
linearize plan = go (planStepList plan)
  where
    o = planOrder plan
    motivators = IS.fromList [m | Just m <- map frameMotivator (IM.elems (planFrames plan)), m /= initStepId]
    leadsToMotivator sid = not (IS.disjoint motivators (successors o sid))
    go [] = []
    go remaining =
      let ready = [s | s <- remaining, not (any (\r -> before o (stepId r) (stepId s)) remaining)]
          pick = minimumBy (comparing rank) ready
       in pick : go (filter ((/= stepId pick) . stepId) remaining)
    rank s
      | sid == initStepId = (0 :: Int, sid)
      | sid == goalStepId = (4, sid)
      | IS.member sid motivators = (1, sid)
      | leadsToMotivator sid = (2, sid)
      | otherwise = (3, sid)
      where
        sid = stepId s
