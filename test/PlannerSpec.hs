module PlannerSpec (spec) where

import Data.IntMap.Strict qualified as IM
import Data.IntSet qualified as IS
import FetchDomain
import Helpers
import IPOCL
import IPOCL.Bindings
import IPOCL.Domains.Aladdin
import IPOCL.Domains.Bribe
import IPOCL.Domains.Tiny
import IPOCL.Domains.Tower
import IPOCL.Order
import IPOCL.Refine
import IPOCL.Search
import IPOCL.Syntax (Problem, problemName)
import Test.Hspec hiding (before)

planIsConsistent :: Plan -> Expectation
planIsConsistent plan = do
  let o = planOrder plan
      b = planBindings plan
  [(x, y) | (x, y) <- orderPairs o, before o y x] `shouldBe` []
  [(x, y) | (x, y) <- neqConstraints b, necessarilyEqual b x y] `shouldBe` []

-- | Along a sampled search path, every visited plan and each of its children
-- has exactly the from-scratch threats, in the same order.
threatsAgree :: Problem -> Expectation
threatsAgree p = do
  let name = problemName p
  [() | plan <- sampled, causalThreats plan /= causalThreatsFromScratch plan] `shouldBe` []
  (name, all (null . causalThreatsFromScratch) sampled) `shouldBe` (name, False)
  where
    sampled =
      [ plan
      | parent <- take 1500 [evPlan e | e@Visited {} <- search env defaultSearchConfig (initialPlan p)]
      , plan <- parent : children parent
      ]
    env = mkEnv p
    children plan = case expand env plan of
      Refined _ cs -> map childPlan cs
      _ -> []

spec :: Spec
spec = do
  describe "search" $ do
    it "solves the tiny problem with a single step" $ do
      plan <- firstStory tinyProblem
      storyLabels plan `shouldBe` ["wake-up(hero)"]
      plan `shouldBeValidFor` tinyProblem
    it "never visits a plan with cyclic orderings or inconsistent bindings" $
      mapM_ planIsConsistent (take 2000 [evPlan e | e <- search (mkEnv motivatedTowerProblem) defaultSearchConfig (initialPlan motivatedTowerProblem)])
    it "keeps recorded threats equal to threats computed from scratch" $
      mapM_ threatsAgree [towerProblem, motivatedTowerProblem, aladdinProblem]
    it "returns only valid plans across several solutions" $ do
      let r = solvePure defaultSolveConfig {cfgCount = 5, cfgMaxExpanded = Just 20000} bribeProblem
      length (resultStories r) `shouldSatisfy` (>= 2)
      mapM_ (`shouldBeValidFor` bribeProblem) (resultStories r)

  describe "intentionality" $ do
    it "finds no believable tower story when nothing can motivate the characters" $
      resultEnd (solveWith towerProblem) `shouldBe` Exhausted
    it "motivates a Frame from an Intention in the initial state" $ do
      plan <- firstStory tinyProblem
      frameSummary plan `shouldBe` [("hero", "awake(hero)", ["wake-up(hero)"], "init")]
      plan `shouldBeValidFor` tinyProblem
    it "tells the motivated tower story with every action inside a Frame" $ do
      plan <- firstStory motivatedTowerProblem
      plan `shouldBeValidFor` motivatedTowerProblem
      frameSummary plan
        `shouldMatchList` [ ("king", "locked(princess)", ["lock-in-tower(king, princess)"], "disobey(princess, king)")
                          , ("knight", "¬alive(king)", ["kill(knight, king)"], "witness-cruelty(knight, king, princess)")
                          ]
    it "passes a goal to another Character through a literal-valued parameter" $ do
      plan <- firstStory fetchProblem
      plan `shouldBeValidFor` fetchProblem
      frameSummary plan
        `shouldContain` [("knight", "has(king, lamp)", ["give(knight, king, lamp)"], "order(king, knight, has(king, lamp))")]
    it "never places a Happening in an Interval" $ do
      plan <- firstStory motivatedTowerProblem
      [s | s <- actionSteps plan, stepHappening s, any (IS.member (stepId s) . frameInterval) (IM.elems (planFrames plan))]
        `shouldSatisfy` null
