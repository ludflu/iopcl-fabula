-- | Author preferences: hard ones prune plans, soft ones add to the heuristic.
module IPOCL.Preferences
  ( violations
  , hardViolated
  , softPenalty
  ) where

import Data.Maybe (isJust)
import Data.Set qualified as Set
import IPOCL.Bindings
import IPOCL.Ground
import IPOCL.Plan
import IPOCL.Syntax

-- | How many times a plan already breaks a rule. Counts only violations that
-- no further refinement can undo, so pruning on them is safe.
violations :: Plan -> PreferenceRule -> Int
violations plan = \case
  AllowGoals c allowed -> count (\g -> not (any (isJust . unifyLiterals b g) allowed)) (goalsOf c)
  ForbidGoal c l -> count (== l) (goalsOf c)
  MaxFrames c n -> max 0 (length (framesOf plan c) - n)
  NoRepeatSteps -> length groundSteps - Set.size (Set.fromList groundSteps)
  where
    b = planBindings plan
    goalsOf c = map (resolvedGoal plan) (framesOf plan c)
    count f = length . filter f
    groundSteps =
      [ (gaIndex g, args)
      | s <- actionSteps plan
      , let args = map (resolve b) (stepArgs s)
      , all (null . termVars) args
      , Just g <- [stepAction s]
      ]

hardViolated :: [Preference] -> Plan -> Bool
hardViolated prefs plan = or [violations plan r > 0 | Preference r Hard <- prefs]

softPenalty :: [Preference] -> Plan -> Int
softPenalty prefs plan = sum [w * violations plan r | Preference r (Soft w) <- prefs]
