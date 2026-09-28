module PlannerSpec (spec) where

import Helpers
import IPOCL
import IPOCL.Domains.Tiny
import Test.Hspec

spec :: Spec
spec = do
  describe "POCL mode" $ do
    it "solves the tiny problem with a single step" $ do
      plan <- firstStory POCL tinyProblem
      storyLabels plan `shouldBe` ["wake-up(hero)"]
      plan `shouldBeValidFor` (POCL, tinyProblem)
