module ParserSpec (spec) where

import Data.List (nub)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import IPOCL.Domains.Aladdin
import IPOCL.Domains.Bribe
import IPOCL.Domains.Tiny
import IPOCL.Domains.Tower
import IPOCL.Parser
import IPOCL.Printer
import IPOCL.Syntax
import System.Exit (ExitCode (..))
import System.Process (readProcessWithExitCode)
import Test.Hspec
import Test.QuickCheck

builtins :: [(String, Problem)]
builtins =
  [ ("tiny", tinyProblem)
  , ("tower", towerProblem)
  , ("motivated-tower", motivatedTowerProblem)
  , ("bribe", bribeProblem)
  , ("aladdin", aladdinProblem)
  ]

domainPath, problemPath :: String -> FilePath
domainPath n = "domains/" <> n <> ".ipocl"
problemPath n = "domains/" <> n <> "-problem.ipocl"

roundTrip :: Problem -> Either Text Problem
roundTrip p = do
  d <- parseDomain "domain" (printDomain (problemDomain p))
  parseProblem d "problem" (printProblem p)

-- | Parse and check a domain and problem given as text.
check :: Text -> Text -> Either Text Problem
check = checkedProblem "d.ipocl" `flip` "p.ipocl"

shouldFailWith :: (Show a) => Either Text a -> Text -> Expectation
shouldFailWith r msg = case r of
  Left e -> e `shouldSatisfy` T.isInfixOf msg
  Right x -> expectationFailure ("expected an error containing " <> show msg <> ", got " <> show x)

oneAction :: Text -> Text
oneAction body = "(define (domain d)\n  (:action a\n" <> body <> "))\n"

simpleProblem :: Text -> Text
simpleProblem prefs = "(define (problem p) (:domain d) (:agents hero) (:init (character hero)) (:goal (done hero))" <> prefs <> ")"

spec :: Spec
spec = do
  describe "domains/*.ipocl" $
    mapM_
      ( \(n, p) -> it (n <> " parses to the built-in problem") $ do
          r <- loadProblem (domainPath n) (problemPath n)
          r `shouldBe` Right p
      )
      builtins

  describe "parseDomain" $ do
    it "treats a missing and as a single literal and () as none" $ do
      let d = parseDomain "x" (oneAction "    :parameters (?x) :actors (?x) :constraints () :precondition (and) :effect (p ?x)")
          fields s = (schemaConstraints s, schemaPrecondition s, schemaEffect s)
      map fields . domainSchemas <$> d `shouldBe` Right [([], [], [lit "p" ["?x"]])]
    it "parses nested literals as literal-valued terms" $ do
      let d = parseDomain "x" (oneAction "    :parameters (?c ?m) :effect (intends ?c (not (alive ?m)))")
      map schemaEffect . domainSchemas <$> d `shouldBe` Right [[intends "?c" (Right (nlit "alive" ["?m"]))]]
    it "reports a parse error with its line and column" $
      parseDomain "bad.ipocl" "(define (domain d)\n  (:action a\n    :parameters (?x\n    :bogus))" `shouldFailWith` "bad.ipocl:4:"
    it "rejects neq outside a precondition" $
      parseDomain "x" (oneAction "    :parameters (?a ?b) :effect (neq ?a ?b)") `shouldFailWith` "neq is only allowed in a precondition"
    it "rejects a repeated field" $
      parseDomain "x" (oneAction "    :parameters (?a) :parameters (?a)") `shouldFailWith` "duplicate :parameters"

  describe "parseProblem" $ do
    it "rejects a problem for a different domain" $
      parseProblem tinyDomain "p" "(define (problem p) (:domain tower))" `shouldFailWith` "tiny"
    it "defaults preferences to soft with weight 10" $ do
      let p = parseProblem tinyDomain "p" "(define (problem p) (:domain tiny) (:agents hero) (:preferences (max-frames hero 1) (forbid-goal hero (not (awake hero)) :hard) (no-repeat-steps :weight 5)))"
      problemPreferences <$> p
        `shouldBe` Right
          [ Preference (MaxFrames (Symbol "hero") 1) (Soft 10)
          , Preference (ForbidGoal (Symbol "hero") (nlit "awake" ["hero"])) Hard
          , Preference NoRepeatSteps (Soft 5)
          ]

  describe "validation" $ do
    let valid = "    :parameters (?x) :actors (?x) :constraints (character ?x)\n"
    it "accepts a valid domain" $
      check (oneAction (valid <> "    :effect (done ?x)")) (simpleProblem "") `shouldSatisfy` either (const False) (const True)
    it "rejects intends in a precondition" $
      check (oneAction (valid <> "    :precondition (intends ?x (done ?x)) :effect (done ?x)")) (simpleProblem "")
        `shouldFailWith` "d.ipocl:2:12: action a: intends may not appear in a precondition"
    it "rejects an effect of not intends" $
      check (oneAction (valid <> "    :effect (not (intends ?x (done ?x)))")) (simpleProblem "")
        `shouldFailWith` "action a: an effect may not negate an intention"
    it "rejects an effect that negates a static predicate" $
      check (oneAction (valid <> "    :effect (and (done ?x) (not (character ?x)))")) (simpleProblem "")
        `shouldFailWith` "changes the static predicate character"
    it "rejects an actor that is not a parameter" $
      check (oneAction "    :parameters (?x) :actors (?y) :constraints (character ?x) :effect (done ?x)") (simpleProblem "")
        `shouldFailWith` "action a: actor ?y is not a parameter"
    it "rejects an unknown character in a preference" $
      check (oneAction (valid <> "    :effect (done ?x)")) (simpleProblem "\n  (:preferences (max-frames villain 2))")
        `shouldFailWith` "p.ipocl:2:17: preference names unknown character villain"
    it "checks a relevance preference against the declared Protagonist" $ do
      let domain = oneAction (valid <> "    :effect (done ?x)")
      check domain (simpleProblem "\n  (:protagonist hero)\n  (:preferences (third-rail))") `shouldSatisfy` either (const False) (const True)
      check domain (simpleProblem "\n  (:preferences (third-rail))") `shouldFailWith` "p.ipocl:2:17: preference third-rail needs a protagonist"
    it "blames the problem file for problem issues outside preferences" $
      check (oneAction (valid <> "    :effect (done ?x)")) (simpleProblem "\n  (:protagonist hero)\n  (:desire (done hero))")
        `shouldFailWith` "p.ipocl: the protagonist hero does not intend the desire done(hero) in the initial state"
    it "reports unreadable files" $ do
      r <- loadProblem "domains/no-such-file.ipocl" "domains/tiny-problem.ipocl"
      r `shouldFailWith` "no-such-file"

  describe "printer" $ do
    mapM_ (\(n, p) -> it ("round-trips " <> n) $ roundTrip p `shouldBe` Right p) builtins
    it "round-trips generated problems" $
      property $ \(GenProblem p) -> roundTrip p === Right p

  describe "solve CLI" $ do
    it "solves the motivated Tower files" $ do
      (code, out, _) <- readProcessWithExitCode "narrative-planning" ["solve", domainPath "motivated-tower", problemPath "motivated-tower"] ""
      code `shouldBe` ExitSuccess
      out `shouldContain` "Story 1"
    it "no longer accepts a planning mode" $ do
      (code, _, err) <- readProcessWithExitCode "narrative-planning" ["solve", domainPath "tower", problemPath "tower", "--mode", "pocl"] ""
      code `shouldBe` ExitFailure 1
      err `shouldContain` "Invalid option"
    it "reports load errors on stderr and exits 1" $ do
      (code, out, err) <- readProcessWithExitCode "narrative-planning" ["solve", domainPath "tower", domainPath "tower"] ""
      code `shouldBe` ExitFailure 1
      out `shouldBe` ""
      err `shouldContain` "domains/tower.ipocl:3:"

-- Generators ----------------------------------------------------------------

newtype GenProblem = GenProblem Problem
  deriving (Show)

instance Arbitrary GenProblem where
  arbitrary = GenProblem <$> genProblem

identifier :: Gen Text
identifier = do
  c <- elements ['a' .. 'z']
  cs <- resize 6 (listOf (elements (['a' .. 'z'] ++ ['0' .. '9'] ++ "-_")))
  let n = T.pack (c : cs)
  if n `elem` ["and", "not", "neq"] then identifier else pure n

genVars :: Gen [Var]
genVars = map (`Var` 0) . nub <$> resize 4 (listOf identifier)

small :: Gen a -> Gen [a]
small = resize 3 . listOf

genTerm :: [Var] -> Int -> Gen Term
genTerm vs depth =
  frequency $
    [(3, TSym . Symbol <$> identifier)]
      ++ [(3, TVar <$> elements vs) | not (null vs)]
      ++ [(1, TLit <$> genLiteral vs (depth - 1)) | depth > 0]

genAtom :: [Var] -> Int -> Gen Atom
genAtom vs depth = Atom <$> identifier <*> small (genTerm vs depth)

genLiteral :: [Var] -> Int -> Gen Literal
genLiteral vs depth = Literal <$> arbitrary <*> genAtom vs depth

genPrecond :: [Var] -> Gen Precond
genPrecond vs = frequency [(4, PLit <$> genLiteral vs 2), (1, PNeq <$> genTerm vs 0 <*> genTerm vs 0)]

genTemplate :: Gen Template
genTemplate = template . T.concat <$> small (oneof [pure "?", ("?" <>) <$> identifier, T.pack <$> listOf (elements "ab .,\"\\?-;()")])

genSchema :: Gen ActionSchema
genSchema = do
  params <- genVars
  actors <- sublistOf params
  ActionSchema
    <$> identifier
    <*> pure params
    <*> pure actors
    <*> arbitrary
    <*> small (genAtom params 0)
    <*> small (genPrecond params)
    <*> small (genLiteral params 2)
    <*> oneof [pure Nothing, Just <$> genTemplate]
    <*> oneof [pure Nothing, Just <$> genTemplate]

genDomain :: Gen Domain
genDomain =
  Domain
    <$> identifier
    <*> small genSchema
    <*> small (PredicateText <$> identifier <*> genVars <*> genTemplate)

genPreference :: Gen Preference
genPreference = Preference <$> rule <*> strength
  where
    who = Symbol <$> identifier
    rule =
      oneof
        [ AllowGoals <$> who <*> small (genLiteral [] 2)
        , ForbidGoal <$> who <*> genLiteral [] 2
        , MaxFrames <$> who <*> chooseInt (0, 10)
        , pure NoRepeatSteps
        , pure ThirdRail
        , ServesProtagonist <$> who
        , MaxBackstory <$> chooseInt (0, 10)
        , pure MisbeliefBlocks
        ]
    strength = oneof [pure Hard, Soft <$> chooseInt (0, 10000)]

genProblem :: Gen Problem
genProblem =
  Problem
    <$> identifier
    <*> genDomain
    <*> (Set.fromList <$> small (Symbol <$> identifier))
    <*> (Set.fromList <$> small (genAtom [] 2))
    <*> small (genLiteral [] 2)
    <*> small genPreference
    <*> small (RequiredFrame . Symbol <$> identifier <*> genLiteral [] 2 <*> arbitrary)
    <*> oneof [pure Nothing, Just . Symbol <$> identifier]
    <*> oneof [pure Nothing, Just <$> genLiteral [] 2]
    <*> small (genAtom [] 2)
    <*> small (genAtom [] 2)
    <*> oneof [pure defaultBackstoryCost, BackstoryCost <$> chooseInt (0, 20) <*> chooseInt (0, 20)]
