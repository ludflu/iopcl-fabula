module PreferenceSpec (spec) where

import Control.Monad (forM_)
import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import Helpers
import IPOCL
import IPOCL.Domains.Bribe
import IPOCL.Domains.Tiny
import IPOCL.Preferences
import IPOCL.Syntax
import SmallDomains
import Test.Hspec

-- | The bard can please the king by singing or with a gift, and intends both
-- that the king is happy and that the king is rich.
giftProblem :: Problem
giftProblem =
  problem
    "gift"
    Domain
      { domainName = "gift"
      , domainSchemas =
          [ (schema "sing" ["?who"])
              { schemaActors = [Var "who" 0]
              , schemaConstraints = [atom "character" ["?who"]]
              , schemaEffect = [lit "happy" ["king"]]
              }
          , (schema "give-gold" ["?who"])
              { schemaActors = [Var "who" 0]
              , schemaConstraints = [atom "character" ["?who"]]
              , schemaEffect = [lit "happy" ["king"], lit "rich" ["king"]]
              }
          ]
      , domainPredicateTexts = []
      }
    ["bard"]
    [ atom "character" ["bard"]
    , litAtom (intends "bard" (Right (lit "happy" ["king"])))
    , litAtom (intends "bard" (Right (lit "rich" ["king"])))
    ]
    [lit "happy" ["king"]]

withPrefs :: [Preference] -> Problem -> Problem
withPrefs prefs p = p {problemPreferences = prefs}

goals :: Plan -> [(Text, Text)]
goals plan = [(c, g) | (c, g, _, _) <- frameSummary plan]

-- | Hard preferences can leave an infinite space with no Story in it.
limited :: Problem -> Result
limited = solvePure defaultSolveConfig {cfgMaxExpanded = Just 1000}

hard, soft :: PreferenceRule -> Preference
hard r = Preference r Hard
soft r = Preference r (Soft 10)

-- | A solved plan with its one Step duplicated.
repeated :: IO Plan
repeated = do
  plan <- firstStory IPOCL tinyProblem
  let s = head' (actionSteps plan)
      s' = s {stepId = planNextStep plan}
  pure plan {planSteps = IM.insert (stepId s') s' (planSteps plan), planNextStep = planNextStep plan + 1}
  where
    head' = \case
      x : _ -> x
      [] -> error "no steps"

spec :: Spec
spec = do
  describe "on the planner" $ do
    it "finds a Story without a Character goal once a hard forbid-goal rules it out" $ do
      before' <- firstStory IPOCL giftProblem
      goals before' `shouldContain` [("bard", "rich(king)")]
      let p = withPrefs [hard (ForbidGoal "bard" (lit "rich" ["king"]))] giftProblem
      after' <- firstStory IPOCL p
      goals after' `shouldNotContain` [("bard", "rich(king)")]
      after' `shouldBeValidFor` (IPOCL, p)
    it "lets a soft preference change the first Story" $ do
      let p = withPrefs [soft (ForbidGoal "bard" (lit "rich" ["king"]))] giftProblem
      story <- firstStory IPOCL p
      goals story `shouldNotContain` [("bard", "rich(king)")]
    forM_
      [ ("forbid-goal", ForbidGoal "villain" (lit "controls" ["villain", "president"]))
      , ("allow-goals", AllowGoals "hero" [])
      , ("max-frames", MaxFrames "villain" 0)
      ]
      $ \(name, rule) ->
        it ("keeps a solvable problem solvable under a soft " <> name <> " it must violate") $ do
          resultOutcome (limited (withPrefs [hard rule] bribeProblem)) `shouldNotBe` Solved
          resultOutcome (limited (withPrefs [soft rule] bribeProblem)) `shouldBe` Solved
    it "leaves Characters without an allow-goals entry unrestricted" $ do
      let p = withPrefs [hard (AllowGoals "hero" [lit "has" ["villain", "money"]])] bribeProblem
      story <- firstStory IPOCL p
      goals story `shouldContain` [("villain", "controls(villain, president)")]
    it "needs two Frames when one Character must change its mind" $ do
      resultOutcome (limited (withPrefs [hard (MaxFrames "hero" 1)] sleepyProblem)) `shouldNotBe` Solved
      resultOutcome (limited (withPrefs [hard (MaxFrames "hero" 2)] sleepyProblem)) `shouldBe` Solved
  describe "violations" $ do
    it "counts Frames whose goal is forbidden" $ do
      story <- firstStory IPOCL bribeProblem
      violations story (ForbidGoal "hero" (lit "has" ["villain", "money"])) `shouldBe` 1
      violations story (ForbidGoal "hero" (lit "has" ["hero", "money"])) `shouldBe` 0
    it "counts Frames whose goal is outside the whitelist" $ do
      story <- firstStory IPOCL bribeProblem
      violations story (AllowGoals "villain" [lit "controls" ["villain", "president"]]) `shouldBe` 0
      violations story (AllowGoals "villain" []) `shouldBe` 1
    it "counts Frames over the cap" $ do
      story <- firstStory IPOCL bribeProblem
      violations story (MaxFrames "villain" 0) `shouldBe` 1
      violations story (MaxFrames "villain" 1) `shouldBe` 0
    it "counts repeated ground Steps" $ do
      story <- firstStory IPOCL tinyProblem
      violations story NoRepeatSteps `shouldBe` 0
      twice <- repeated
      violations twice NoRepeatSteps `shouldBe` 1
    forM_
      [ ("forbid-goal", ForbidGoal "hero" (lit "has" ["villain", "money"]))
      , ("allow-goals", AllowGoals "hero" [])
      , ("max-frames", MaxFrames "hero" 0)
      ]
      $ \(name, rule) -> it ("prunes a hard " <> name <> " and charges a soft one") $ do
        story <- firstStory IPOCL bribeProblem
        hardViolated [hard rule] story `shouldBe` True
        softPenalty [hard rule] story `shouldBe` 0
        hardViolated [soft rule] story `shouldBe` False
        softPenalty [soft rule] story `shouldBe` 10
    it "prunes a hard no-repeat-steps and charges a soft one" $ do
      twice <- repeated
      hardViolated [hard NoRepeatSteps] twice `shouldBe` True
      hardViolated [soft NoRepeatSteps] twice `shouldBe` False
      softPenalty [Preference NoRepeatSteps (Soft 7)] twice `shouldBe` 7
