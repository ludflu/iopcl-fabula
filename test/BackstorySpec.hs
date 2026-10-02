module BackstorySpec (spec) where

import Data.List (isInfixOf)
import Data.Set qualified as Set
import Data.Text qualified as T
import Helpers
import IPOCL
import IPOCL.Bindings
import IPOCL.DomainCheck
import IPOCL.Heuristic
import IPOCL.Parser
import IPOCL.Preferences
import IPOCL.Printer
import IPOCL.Report
import IPOCL.Signature
import IPOCL.Syntax
import IPOCL.Validate
import Test.Hspec

-- | Nora wants Ruby out of the house, which only its owner can manage.
houseProblem :: Problem
houseProblem =
  problem
    "house"
    Domain
      { domainName = "house"
      , domainSchemas =
          [ (schema "evict" ["?o", "?t", "?h"])
              { schemaActors = [Var "o" 0]
              , schemaConstraints = [atom "character" ["?o"], atom "character" ["?t"], atom "house" ["?h"]]
              , schemaPrecondition = [PLit (lit "owns" ["?o", "?h"]), PLit (lit "lives-in" ["?t", "?h"])]
              , schemaEffect = [nlit "lives-in" ["?t", "?h"], lit "homeless" ["?t"]]
              }
          , (schema "sell" ["?o", "?h"])
              { schemaActors = [Var "o" 0]
              , schemaConstraints = [atom "character" ["?o"], atom "house" ["?h"]]
              , schemaPrecondition = [PLit (lit "owns" ["?o", "?h"])]
              , schemaEffect = [nlit "owns" ["?o", "?h"]]
              }
          ]
      , domainPredicateTexts = []
      }
    ["nora", "ruby"]
    [ atom "character" ["nora"]
    , atom "character" ["ruby"]
    , atom "house" ["house"]
    , atom "lives-in" ["ruby", "house"]
    , litAtom (intends "nora" (Right (lit "homeless" ["ruby"])))
    , litAtom (intends "nora" (Right (nlit "owns" ["nora", "house"])))
    ]
    [lit "homeless" ["ruby"]]

owns :: Atom
owns = atom "owns" ["nora", "house"]

withBackstory :: Problem -> Problem
withBackstory p = p {problemBackstory = [owns]}

softPenaltyOf :: Problem -> Plan -> Int
softPenaltyOf p = softPenalty p (problemPreferences p)

limited :: Problem -> Result
limited = solvePure defaultSolveConfig {cfgMaxExpanded = Just 3000}

stories :: Problem -> [Plan]
stories = resultStories . solvePure defaultSolveConfig {cfgMaxExpanded = Just 3000, cfgCount = 10}

spec :: Spec
spec = describe "backstory on demand" $ do
  describe "syntax and checks" $ do
    it "round-trips possible backstory and its costs" $ do
      let p = (withBackstory houseProblem) {problemBackstoryCost = BackstoryCost 1 2, problemPreferences = [Preference (MaxBackstory 1) Hard]}
          text = printProblem p
      T.unpack text `shouldSatisfy` isInfixOf "(:possible-backstory\n    (owns nora house))"
      T.unpack text `shouldSatisfy` isInfixOf "(:backstory-cost :fact 1 :intention 2)"
      d <- either (fail . T.unpack) pure (parseDomain "d" (printDomain (problemDomain p)))
      parseProblem d "p" (printProblem p {problemDomain = d}) `shouldBe` Right p {problemDomain = d}
    it "rejects backstory that already holds or uses a constraint predicate" $ do
      checkProblem houseProblem {problemBackstory = [atom "lives-in" ["ruby", "house"]]}
        `shouldBe` ["possible backstory lives-in(ruby, house) already holds in the initial state"]
      checkProblem houseProblem {problemBackstory = [atom "house" ["shed"]]}
        `shouldBe` ["possible backstory house(shed) uses the constraint predicate house"]
      checkProblem (withBackstory houseProblem) `shouldBe` []

  describe "planning" $ do
    it "solves a problem that needs a missing fact, and reports it" $ do
      resultEnd (limited houseProblem) `shouldBe` Exhausted
      s <- firstStory IPOCL (withBackstory houseProblem)
      planBackstory s `shouldBe` Set.singleton owns
      storyLabels s `shouldBe` ["evict(nora, ruby, house)"]
      T.unpack (renderPlan s) `shouldSatisfy` isInfixOf "Backstory:\n  owns(nora, house)\n"
    it "gives committed or possible backstory no closed-world support for its negation" $ do
      let needsBoth = (withBackstory houseProblem) {problemOutcome = [lit "homeless" ["ruby"], nlit "owns" ["nora", "house"]]}
          unsellable = needsBoth {problemDomain = (problemDomain needsBoth) {domainSchemas = take 1 (domainSchemas (problemDomain needsBoth))}}
      resultEnd (limited unsellable) `shouldBe` Exhausted
      s <- firstStory IPOCL needsBoth
      storyLabels s `shouldBe` ["evict(nora, ruby, house)", "sell(nora, house)"]
      s `shouldBeValidFor` (IPOCL, needsBoth)
    it "passes validation with the committed literals in the initial state" $ do
      let p = withBackstory houseProblem
          ss = stories p
      length ss `shouldSatisfy` (> 0)
      mapM_ (`shouldBeValidFor` (IPOCL, p)) ss
      mapM_ (\s -> validatePlan IPOCL houseProblem s `shouldContain` ["backstory owns(nora, house) is not possible backstory"]) ss
    it "makes backstory part of the story signature" $ do
      s <- firstStory IPOCL (withBackstory houseProblem)
      let other = s {planBackstory = Set.insert (atom "owns" ["ruby", "house"]) (planBackstory s)}
      storySignature other `shouldNotBe` storySignature s
      planSignature other `shouldNotBe` planSignature s
    it "charges commitment cost in the heuristic" $ do
      let p = (withBackstory houseProblem) {problemBackstory = [owns, Atom intendsPredicate [TSym "ruby", TLit (lit "homeless" ["nora"])]]}
          r = problemReachability p
      literalCost r emptyBindings (pos owns) `shouldBe` Just 3
      literalCost r emptyBindings (lit "homeless" ["ruby"]) `shouldBe` Just 4
      literalCost r emptyBindings (intends "ruby" (Right (lit "homeless" ["nora"]))) `shouldBe` Just 7
      literalCost (problemReachability houseProblem) emptyBindings (pos owns) `shouldBe` Nothing
    it "caps commitments with max-backstory" $ do
      let capped s = (withBackstory houseProblem) {problemPreferences = [Preference (MaxBackstory 0) s]}
      resultEnd (limited (capped Hard)) `shouldBe` Exhausted
      s <- firstStory IPOCL (capped (Soft 10))
      planBackstory s `shouldBe` Set.singleton owns
      softPenaltyOf (capped (Soft 10)) s `shouldBe` 10
      softPenaltyOf (withBackstory houseProblem) {problemPreferences = [Preference (MaxBackstory 1) (Soft 10)]} s `shouldBe` 0

