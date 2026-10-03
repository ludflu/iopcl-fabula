-- | Plain-text plan listing: ordered Steps, then Frames.
module IPOCL.Report
  ( renderPlan
  ) where

import Data.IntMap.Strict qualified as IM
import Data.IntSet qualified as IS
import Data.Maybe (isJust)
import Data.Set qualified as Set
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
         | (i, s) <- zip [1 :: Int ..] (filter isActionStep (linearize plan))
         ]
      ++ (if Set.null (planBackstory plan) then [] else "Backstory:" : ["  " <> prettyAtom a | a <- Set.toList (planBackstory plan)])
      ++ (if IM.null (planFrames plan) then [] else "Frames:" : map frameLine (IM.elems (planFrames plan)))
  where
    happeningMark s
      | isUnexecuted plan (stepId s) = "  (attempt, blocked)"
      | stepHappening s = "  (happening)"
      | otherwise = ""
    label sid = maybe "?" (stepLabel plan) (IM.lookup sid (planSteps plan))
    frameLine f =
      "  "
        <> symbolText (frameCharacter f)
        <> " wants "
        <> prettyLiteral (resolvedGoal plan f)
        <> (if isJust (frameAttempt f) then " (fails)" else "")
        <> ": "
        <> T.intercalate ", " [label s | s <- map stepId (linearize plan), IS.member s (frameInterval f)]
        <> "  [motivated by "
        <> maybe "nothing" (\m -> if m == initStepId then "the initial state" else label m) (frameMotivator f)
        <> "]"
