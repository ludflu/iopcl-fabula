module PlannerSpec (spec) where

import Helpers
import IPOCL
import IPOCL.Bindings
import IPOCL.Domains.Tiny
import IPOCL.Domains.Tower
import IPOCL.Order
import IPOCL.Refine
import IPOCL.Search
import Test.Hspec hiding (before)

planIsConsistent :: Plan -> Expectation
planIsConsistent plan = do
  let o = planOrder plan
      b = planBindings plan
  [(x, y) | (x, y) <- orderPairs o, before o y x] `shouldBe` []
  [(x, y) | (x, y) <- neqConstraints b, necessarilyEqual b x y] `shouldBe` []

spec :: Spec
spec = do
  describe "POCL mode" $ do
    it "solves the tiny problem with a single step" $ do
      plan <- firstStory POCL tinyProblem
      storyLabels plan `shouldBe` ["wake-up(hero)"]
      plan `shouldBeValidFor` (POCL, tinyProblem)
    it "solves the tower problem, resolving threats between killing and locking up" $ do
      plan <- firstStory POCL towerProblem
      plan `shouldBeValidFor` (POCL, towerProblem)
    it "never visits a plan with cyclic orderings or inconsistent bindings" $
      mapM_ planIsConsistent (take 2000 [evPlan e | e <- search (mkEnv POCL towerProblem) defaultSearchConfig (initialPlan towerProblem)])
    it "returns only valid plans across several solutions" $ do
      let r = solvePure defaultSolveConfig {cfgMode = POCL, cfgCount = 5, cfgMaxExpanded = Just 20000} towerProblem
      length (resultStories r) `shouldBe` 5
      mapM_ (`shouldBeValidFor` (POCL, towerProblem)) (resultStories r)
