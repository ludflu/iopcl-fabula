module GroundSpec (spec) where

import Data.Text (Text)
import IPOCL.DomainCheck
import IPOCL.Domains.Aladdin
import IPOCL.Domains.Bribe
import IPOCL.Domains.Tiny
import IPOCL.Domains.Tower
import IPOCL.Ground
import IPOCL.Syntax
import Test.Hspec

labelsOf :: Text -> Problem -> [Text]
labelsOf n p = [groundActionLabel g | g <- groundActions p, schemaName (gaSchema g) == n]

spec :: Spec
spec = do
  it "enumerates one ground action per legal constraint binding" $
    labelsOf "travel" aladdinProblem
      `shouldMatchList` [ "travel(" <> c <> ", " <> a <> ", " <> b <> ")"
                        | c <- ["aladdin", "jafar", "jasmine", "dragon", "genie"]
                        , (a, b) <- [("castle", "mountain"), ("mountain", "castle")]
                        ]
  it "drops bindings that violate a ground non-codesignation" $
    labelsOf "kill" towerProblem `shouldNotContain` ["kill(king, king)"]
  it "leaves literal-valued parameters lifted" $
    labelsOf "coerce" bribeProblem `shouldBe` ["coerce(villain, hero, ?objective)"]
  it "grounds the tiny problem to a single action" $
    labelsOf "wake-up" tinyProblem `shouldBe` ["wake-up(hero)"]
  it "represents every construct of the Aladdin domain" $
    checkProblem aladdinProblem `shouldBe` []
  it "accepts every built-in problem" $
    concatMap checkProblem [tinyProblem, towerProblem, motivatedTowerProblem, bribeProblem] `shouldBe` []
