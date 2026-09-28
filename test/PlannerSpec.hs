module PlannerSpec (spec) where

import Data.IntMap.Strict qualified as IM
import Data.IntSet qualified as IS
import FetchDomain
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

  describe "IPOCL mode" $ do
    it "finds no believable tower story when nothing can motivate the characters" $
      resultEnd (solveWith IPOCL towerProblem) `shouldBe` Exhausted
    it "motivates a Frame from an Intention in the initial state" $ do
      plan <- firstStory IPOCL tinyProblem
      frameSummary plan `shouldBe` [("hero", "awake(hero)", ["wake-up(hero)"], "init")]
      plan `shouldBeValidFor` (IPOCL, tinyProblem)
    it "tells the motivated tower story with every action inside a Frame" $ do
      plan <- firstStory IPOCL motivatedTowerProblem
      plan `shouldBeValidFor` (IPOCL, motivatedTowerProblem)
      frameSummary plan
        `shouldMatchList` [ ("king", "locked(princess)", ["lock-in-tower(king, princess)"], "disobey(princess, king)")
                          , ("knight", "¬alive(king)", ["kill(knight, king)"], "witness-cruelty(knight, king, princess)")
                          ]
    it "passes a goal to another Character through a literal-valued parameter" $ do
      plan <- firstStory IPOCL fetchProblem
      plan `shouldBeValidFor` (IPOCL, fetchProblem)
      frameSummary plan
        `shouldContain` [("knight", "has(king, lamp)", ["give(knight, king, lamp)"], "order(king, knight, has(king, lamp))")]
    it "never places a Happening in an Interval" $ do
      plan <- firstStory IPOCL motivatedTowerProblem
      [s | s <- actionSteps plan, stepHappening s, any (IS.member (stepId s) . frameInterval) (IM.elems (planFrames plan))]
        `shouldSatisfy` null
