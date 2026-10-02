-- | Search traces in the style of Appendix A.3.
module IPOCL.Trace
  ( formatEvent
  , describeFlaw
  ) where

import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import Data.Text qualified as T
import IPOCL.Bindings
import IPOCL.Plan
import IPOCL.Pretty
import IPOCL.Search
import IPOCL.Syntax

formatEvent :: SearchEvent -> Text
formatEvent = \case
  Visited {..} ->
    T.unlines
      [ "plan " <> tshow evNode <> maybe "" (\p -> " (child of plan " <> tshow p <> ")") evParent
      , "  reason: " <> evReason
      , case (evFlaw, evDeadEnd) of
          (Just f, False) -> "  now working on: " <> describeFlaw evPlan f
          (Just f, True) -> "  dead end: no way to repair " <> describeFlaw evPlan f
          (Nothing, True) -> "  dead end: orphans remain: " <> T.intercalate ", " [label s <> " for " <> symbolText a | (s, a) <- orphans evPlan]
          (Nothing, False) -> "  complete"
      , "  children: " <> tshow evChildren
      ]
    where
      label s = maybe "?" (stepLabel evPlan) (IM.lookup s (planSteps evPlan))
  FoundSolution {..} -> "solution found: plan " <> tshow evNode <> "\n"

describeFlaw :: Plan -> Flaw -> Text
describeFlaw plan = \case
  OpenCondition s l -> "open condition " <> showLit l <> " on step " <> tshow s
  CausalThreat t l ->
    "causal threat on "
      <> showLit (linkCond l)
      <> " between "
      <> tshow (linkFrom l)
      <> " and "
      <> tshow (linkTo l)
      <> ", clobbered by step "
      <> tshow t
  OpenMotivation f -> "open motivation " <> maybe "?" (showLit . frameIntention) (frame f) <> " on frame " <> tshow f
  IntentFlaw s f ->
    "intent flaw for "
      <> maybe "?" (symbolText . frameCharacter) (frame f)
      <> ", to possibly link step "
      <> tshow s
      <> " to frame "
      <> tshow f
      <> maybe "" (\fr -> ": " <> symbolText (frameCharacter fr) <> " intends " <> showLit (frameGoal fr)) (frame f)
  IntentionalThreat a b -> "intentional threat between frame " <> tshow a <> " and frame " <> tshow b
  OpenAttempt s -> "open attempt for the fail-first required frame on step " <> tshow s
  where
    frame f = IM.lookup f (planFrames plan)
    showLit = prettyLiteral . resolveLiteral (planBindings plan)

tshow :: (Show a) => a -> Text
tshow = T.pack . show
