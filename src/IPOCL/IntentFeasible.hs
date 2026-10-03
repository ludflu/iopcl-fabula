-- | Monotone checks on whether an intent flaw can still adopt (ADR-0009).
module IPOCL.IntentFeasible
  ( intentAdoptForeverImpossible
  ) where

import Control.Monad (foldM)
import Data.IntMap.Strict qualified as IM
import Data.IntSet qualified as IS
import Data.Set qualified as Set
import IPOCL.Order
import IPOCL.Plan

-- | True when the adopt branch of 'resolveIntentFlaw' would fail on the
-- required frame orderings: the same @addOrder@ fold as adopt, and future
-- orderings cannot undo a cycle.
intentAdoptForeverImpossible :: Plan -> StepId -> FrameId -> Bool
intentAdoptForeverImpossible plan s c =
  case intentAdoptOrder plan s c of
    Just _ -> False
    Nothing -> True

intentAdoptOrder :: Plan -> StepId -> FrameId -> Maybe Order
intentAdoptOrder plan s c = do
  f <- IM.lookup c (planFrames plan)
  let members g = maybe [] (IS.toList . frameInterval) (IM.lookup g (planFrames plan))
      frameOrder = Set.toList (planFrameOrder plan)
      orderings =
        [(m, s) | Just m <- [frameMotivator f]]
          ++ [(s, fin) | Just fin <- [frameEnd f], fin /= s]
          ++ [(s, x) | (a, later) <- frameOrder, a == c, x <- members later]
          ++ [(x, s) | (earlier, b) <- frameOrder, b == c, x <- members earlier]
  foldM (\acc (x, y) -> addOrder x y acc) (planOrder plan) orderings
