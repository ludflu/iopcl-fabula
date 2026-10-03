module RequiredSpec (spec) where

import Data.IntMap.Strict qualified as IM
import Data.List (isInfixOf)
import Data.Text qualified as T
import Helpers
import IPOCL
import IPOCL.Domains.Bribe
import IPOCL.DomainCheck
import IPOCL.Lint
import IPOCL.Narrate
import IPOCL.Parser
import IPOCL.Printer
import IPOCL.Signature
import IPOCL.Syntax
import IPOCL.Validate
import SmallDomains
import Test.Hspec

requiring :: [(Symbol, Literal)] -> Problem -> Problem
requiring rs p = p {problemRequiredFrames = [RequiredFrame c g False | (c, g) <- rs]}

stories :: Problem -> [Plan]
stories = resultStories . solvePure defaultSolveConfig {cfgMaxExpanded = Just 5000, cfgCount = 20}

-- | The bard may only sing; gold can only come from the jester or by luck.
luckProblem :: Problem
luckProblem =
  problem
    "luck"
    Domain
      { domainName = "luck"
      , domainSchemas =
          [ (schema "sing" ["?who"])
              { schemaActors = [Var "who" 0]
              , schemaConstraints = [atom "character" ["?who"]]
              , schemaEffect = [lit "happy" ["king"]]
              }
          , (schema "give-gold" ["?who"])
              { schemaActors = [Var "who" 0]
              , schemaConstraints = [atom "rich-person" ["?who"]]
              , schemaEffect = [lit "rich" ["king"]]
              }
          , (schema "windfall" [])
              { schemaHappening = True
              , schemaEffect = [lit "rich" ["king"]]
              }
          ]
      , domainPredicateTexts = []
      }
    ["bard", "jester"]
    [ atom "character" ["bard"]
    , atom "character" ["jester"]
    , atom "rich-person" ["jester"]
    , litAtom (intends "bard" (Right (lit "happy" ["king"])))
    , litAtom (intends "bard" (Right (lit "rich" ["king"])))
    , litAtom (intends "jester" (Right (lit "rich" ["king"])))
    ]
    [lit "happy" ["king"]]

spec :: Spec
spec = describe "Required Frames" $ do
  describe "syntax" $ do
    it "parses and prints :required-frames" $ do
      let p = requiring [("hero", lit "has" ["villain", "money"])] bribeProblem
          text = printProblem p
      T.unpack text `shouldSatisfy` isInfixOf "(:required-frames\n    (hero (has villain money)))"
      problemRequiredFrames <$> parseProblem (problemDomain p) "p" text `shouldBe` Right (problemRequiredFrames p)
    it "rejects an unknown Character" $
      checkProblem (requiring [("nobody", lit "has" ["villain", "money"])] bribeProblem)
        `shouldBe` ["required frame names unknown character nobody"]
    it "warns when the goal or the Intention is unreachable" $ do
      problemWarnings (requiring [("hero", lit "has" ["villain", "money"])] bribeProblem) `shouldBe` []
      problemWarnings (requiring [("hero", lit "corrupt" ["hero"])] bribeProblem)
        `shouldBe` ["required frame hero wants corrupt(hero): the goal is unreachable"]
      problemWarnings (requiring [("president", lit "has" ["villain", "money"])] bribeProblem)
        `shouldBe` ["required frame president wants has(villain, money): president can never come to want it"]

  describe "planning" $ do
    it "leaves the Bribe Story unchanged when the Outcome already needs the Frame" $ do
      plain <- firstStory bribeProblem
      let p = requiring [("hero", lit "has" ["villain", "money"])] bribeProblem
      required <- firstStory p
      storyLabels required `shouldBe` storyLabels plain
      frameSummary required `shouldBe` frameSummary plain
      storySignature required `shouldBe` storySignature plain
      narrate p required `shouldBe` narrate bribeProblem plain
      required `shouldBeValidFor` p
    it "adds Steps for a Frame the Outcome does not need" $ do
      plain <- firstStory luckProblem
      storyLabels plain `shouldBe` ["sing(bard)"]
      let p = requiring [("jester", lit "rich" ["king"])] luckProblem
      required <- firstStory p
      required `shouldBeValidFor` p
      [g | (c, g, _, _) <- frameSummary required, c == "jester"] `shouldBe` ["rich(king)"]
      storyLabels required `shouldMatchList` ["sing(bard)", "give-gold(jester)"]
    it "is never satisfied by another Character's Frame or an unintended Step" $ do
      length (stories (requiring [("jester", lit "rich" ["king"])] luckProblem)) `shouldSatisfy` (> 0)
      length (stories (requiring [("bard", lit "rich" ["king"])] luckProblem)) `shouldBe` 0
    it "passes validation for every Story, and validation checks the requirement" $ do
      let p = requiring [("jester", lit "rich" ["king"])] luckProblem
          ss = stories p
      length ss `shouldSatisfy` (> 0)
      mapM_ (`shouldBeValidFor` p) ss
      let unframed s = s {planFrames = IM.filter ((/= "jester") . frameCharacter) (planFrames s)}
      mapM_ (\s -> validatePlan p (unframed s) `shouldSatisfy` elem "required frame jester wants rich(king) is not in the story") ss
    it "allows a later Step to undo the required goal" $ do
      let p = (requiring [("hero", lit "awake" ["hero"])] sleepyProblem) {problemOutcome = [lit "asleep" ["hero"]]}
      s <- firstStory p
      s `shouldBeValidFor` p
      storyLabels s `shouldBe` ["wake-up(hero)", "read(hero)", "fall-asleep(hero)"]
    it "keeps pseudo-steps out of the narration, the Orphans and the step list" $ do
      let p = requiring [("jester", lit "rich" ["king"])] luckProblem
      s <- firstStory p
      orphans s `shouldBe` []
      map stepAction (actionSteps s) `shouldNotContain` [Nothing]
      T.unpack (narrate p s) `shouldNotContain` "required"
