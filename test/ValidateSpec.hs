module ValidateSpec (spec) where

import Data.IntMap.Strict qualified as IM
import Data.Set qualified as Set
import Data.Text qualified as T
import Helpers
import IPOCL
import IPOCL.Domains.Tiny
import IPOCL.Domains.Tower
import IPOCL.Validate
import Test.Hspec

mentions :: T.Text -> [T.Text] -> Bool
mentions needle = any (needle `T.isInfixOf`)

spec :: Spec
spec = do
  it "rejects a plan whose precondition has lost its causal link" $ do
    plan <- firstStory tinyProblem
    let broken = plan {planLinks = Set.filter ((/= goalStepId) . linkTo) (planLinks plan)}
    validatePlan tinyProblem broken `shouldNotBe` []
  it "rejects a plan with a step missing from the ordering towards the goal" $ do
    plan <- firstStory tinyProblem
    let noSteps = plan {planSteps = IM.filterWithKey (\k _ -> k <= goalStepId) (planSteps plan)}
    validatePlan tinyProblem noSteps `shouldNotBe` []
  describe "intentionality" $ do
    it "rejects Orphans" $ do
      plan <- firstStory motivatedTowerProblem
      validatePlan motivatedTowerProblem plan {planFrames = IM.empty}
        `shouldSatisfy` mentions "is not intentional"
    it "rejects an unmotivated Frame" $ do
      plan <- firstStory motivatedTowerProblem
      validatePlan motivatedTowerProblem plan {planFrames = IM.map (\f -> f {frameMotivator = Nothing}) (planFrames plan)}
        `shouldSatisfy` mentions "has no motivating step"
    it "rejects a Motivating step that does not precede the Interval" $ do
      plan <- firstStory motivatedTowerProblem
      validatePlan motivatedTowerProblem plan {planFrames = IM.map (\f -> f {frameMotivator = frameFinal f}) (planFrames plan)}
        `shouldSatisfy` mentions "motivating step does not precede"
