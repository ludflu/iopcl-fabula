module ValidateSpec (spec) where

import Data.IntMap.Strict qualified as IM
import Data.Set qualified as Set
import Helpers
import IPOCL
import IPOCL.Domains.Tiny
import IPOCL.Validate
import Test.Hspec

spec :: Spec
spec = do
  it "rejects a plan whose precondition has lost its causal link" $ do
    plan <- firstStory POCL tinyProblem
    let broken = plan {planLinks = Set.filter ((/= goalStepId) . linkTo) (planLinks plan)}
    validatePlan POCL tinyProblem broken `shouldNotBe` []
  it "rejects a plan with a step missing from the ordering towards the goal" $ do
    plan <- firstStory POCL tinyProblem
    let noSteps = plan {planSteps = IM.filterWithKey (\k _ -> k <= goalStepId) (planSteps plan)}
    validatePlan POCL tinyProblem noSteps `shouldNotBe` []
