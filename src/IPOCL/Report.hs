-- | Plain-text plan listing: ordered Steps, then Frames.
module IPOCL.Report
  ( renderPlan
  ) where

import Data.IntMap.Strict qualified as IM
import Data.IntSet qualified as IS
import Data.Text (Text)
import Data.Text qualified as T
import IPOCL.Linearize
import IPOCL.Plan
import IPOCL.Pretty
import IPOCL.Syntax

renderPlan :: Plan -> Text
renderPlan plan =
  T.unlines $
    ["Steps:"]
      ++ [ "  " <> T.pack (show i) <> ". " <> stepLabel plan s <> happeningMark s
         | (i, s) <- zip [1 :: Int ..] (filter ((> goalStepId) . stepId) (linearize plan))
         ]
      ++ (if IM.null (planFrames plan) then [] else "Frames:" : map frameLine (IM.elems (planFrames plan)))
  where
    happeningMark s = if stepHappening s then "  (happening)" else ""
    label sid = maybe "?" (stepLabel plan) (IM.lookup sid (planSteps plan))
    frameLine f =
      "  "
        <> symbolText (frameCharacter f)
        <> " wants "
        <> prettyLiteral (resolvedGoal plan f)
        <> ": "
        <> T.intercalate ", " [label s | s <- map stepId (linearize plan), IS.member s (frameInterval f)]
        <> "  [motivated by "
        <> maybe "nothing" (\m -> if m == initStepId then "the initial state" else label m) (frameMotivator f)
        <> "]"
