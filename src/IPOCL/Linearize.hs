-- | Total orders consistent with a plan's partial order.
module IPOCL.Linearize
  ( linearize
  ) where

import Data.List (minimumBy)
import Data.Ord (comparing)
import IPOCL.Order
import IPOCL.Plan

-- | A deterministic topological order, init first and goal last. Among ready
-- Steps, Motivating steps come first so intentions are told before they are
-- acted on.
linearize :: Plan -> [Step]
linearize plan = go (planStepList plan)
  where
    o = planOrder plan
    go [] = []
    go remaining =
      let ready = [s | s <- remaining, not (any (\r -> before o (stepId r) (stepId s)) remaining)]
          pick = minimumBy (comparing rank) ready
       in pick : go (filter ((/= stepId pick) . stepId) remaining)
    rank s
      | stepId s == initStepId = (0 :: Int, 0)
      | stepId s == goalStepId = (3, 0)
      | isMotivator plan (stepId s) = (1, stepId s)
      | otherwise = (2, stepId s)
