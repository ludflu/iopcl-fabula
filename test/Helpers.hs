module Helpers
  ( solveWith
  , firstStory
  , storyLabels
  , frameSummary
  , shouldBeValidFor
  ) where

import Data.IntMap.Strict qualified as IM
import Data.IntSet qualified as IS
import Data.Text (Text)
import IPOCL
import IPOCL.Linearize
import IPOCL.Pretty
import IPOCL.Syntax
import IPOCL.Validate
import Test.Hspec

solveWith :: Mode -> Problem -> Result
solveWith m = solvePure defaultSolveConfig {cfgMode = m, cfgMaxExpanded = Just 50000}

firstStory :: Mode -> Problem -> IO Plan
firstStory m p = case resultStories (solveWith m p) of
  s : _ -> pure s
  [] -> expectationFailure "no story found" >> error "unreachable"

-- | Step labels in narration order, without init and goal.
storyLabels :: Plan -> [Text]
storyLabels plan = [stepLabel plan s | s <- linearize plan, stepId s > goalStepId]

-- | (character, goal, interval step labels, motivating step label).
frameSummary :: Plan -> [(Text, Text, [Text], Text)]
frameSummary plan =
  [ ( symbolText (frameCharacter f)
    , prettyLiteral (resolvedGoal plan f)
    , [stepLabel plan s | s <- linearize plan, IS.member (stepId s) (frameInterval f)]
    , maybe "none" label (frameMotivator f)
    )
  | f <- IM.elems (planFrames plan)
  ]
  where
    label m = maybe "?" (stepLabel plan) (IM.lookup m (planSteps plan))

shouldBeValidFor :: Plan -> (Mode, Problem) -> Expectation
shouldBeValidFor plan (m, p) = validatePlan m p plan `shouldBe` []
