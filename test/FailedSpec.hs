module FailedSpec (spec) where

import Data.IntMap.Strict qualified as IM
import Data.IntSet qualified as IS
import Data.List (elemIndex, isInfixOf)
import Data.Maybe (isJust, isNothing)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Helpers
import IPOCL
import IPOCL.Cards
import IPOCL.Dot
import IPOCL.Narrate
import IPOCL.Order qualified as O
import IPOCL.Parser
import IPOCL.Preferences
import IPOCL.Printer
import IPOCL.Refine
import IPOCL.Report
import IPOCL.Signature
import IPOCL.Syntax
import IPOCL.Validate
import Test.Hspec

loadMisbelief :: IO Problem
loadMisbelief =
  loadProblem "domains/misbelief.ipocl" "domains/misbelief-problem.ipocl"
    >>= either (\e -> expectationFailure (T.unpack e) >> error "unreachable") pure

reunited :: Literal
reunited = lit "reunited" ["ruby", "henry"]

failFirst :: Problem -> Problem
failFirst p = p {problemRequiredFrames = problemRequiredFrames p ++ [RequiredFrame "ruby" reunited True]}

-- | The misbelief turningPoint with only the Happening Realization, failing first.
turningPoint :: IO Problem
turningPoint = failFirst . withoutSchemas ["rescue"] <$> loadMisbelief

withoutSchemas :: [Text] -> Problem -> Problem
withoutSchemas names p =
  let d = problemDomain p
   in p {problemDomain = d {domainSchemas = filter ((`notElem` names) . schemaName) (domainSchemas d)}}

limited :: Problem -> Result
limited = solvePure defaultSolveConfig {cfgMaxExpanded = Just 3000}

stories :: Int -> Problem -> [Plan]
stories n = resultStories . solvePure defaultSolveConfig {cfgMaxExpanded = Just 5000, cfgCount = n}

failedFrames :: Plan -> [Frame]
failedFrames plan = [f | f <- IM.elems (planFrames plan), isNothing (frameFinal f)]

-- | Aladdin proposes before Jasmine loves him; marry needs both of them.
proposalProblem :: Problem
proposalProblem =
  (problem "proposal" proposalDomain ["aladdin", "jasmine"] initial [lit "married" ["aladdin", "jasmine"]])
    {problemRequiredFrames = [RequiredFrame "aladdin" (lit "married" ["aladdin", "jasmine"]) True]}
  where
    initial =
      [ atom "character" ["aladdin"]
      , atom "character" ["jasmine"]
      , atom "loves" ["aladdin", "jasmine"]
      , litAtom (intends "aladdin" (Right (lit "married" ["aladdin", "jasmine"])))
      ]
    proposalDomain =
      Domain
        { domainName = "proposal"
        , domainSchemas =
            [ (schema "marry" ["?a", "?b"])
                { schemaActors = [Var "a" 0, Var "b" 0]
                , schemaConstraints = [atom "character" ["?a"], atom "character" ["?b"]]
                , schemaPrecondition = [PLit (lit "loves" ["?a", "?b"]), PLit (lit "loves" ["?b", "?a"]), neq "?a" "?b"]
                , schemaEffect = [lit "married" ["?a", "?b"]]
                }
            , (schema "fall-for" ["?b", "?a"])
                { schemaHappening = True
                , schemaConstraints = [atom "character" ["?a"], atom "character" ["?b"]]
                , schemaPrecondition = [PLit (lit "loves" ["?a", "?b"]), neq "?a" "?b"]
                , schemaEffect = [lit "loves" ["?b", "?a"], intends "?b" (Right (lit "married" ["?a", "?b"]))]
                }
            ]
        , domainPredicateTexts = []
        }

-- | Ruby could also try to elope, which fails for want of a car rather than
-- because of her Misbelief.
elopeProblem :: Problem -> Problem
elopeProblem p =
  let d = problemDomain p
      elope =
        (schema "elope" ["?a", "?b"])
          { schemaActors = [Var "a" 0]
          , schemaConstraints = [atom "character" ["?a"], atom "character" ["?b"]]
          , schemaPrecondition = [PLit (lit "has-car" ["?a"]), neq "?a" "?b"]
          , schemaEffect = [lit "reunited" ["?a", "?b"]]
          }
   in p {problemDomain = d {domainSchemas = elope : domainSchemas d}}

attemptLabels :: Plan -> [Text]
attemptLabels plan = [stepLabel plan s | s <- actionSteps plan, isUnexecuted plan (stepId s)]

spec :: Spec
spec = describe "failed Frames" $ do
  describe "syntax" $ do
    it "round-trips :fail-first and :attempt-text" $ do
      p <- turningPoint
      T.unpack (printProblem p) `shouldSatisfy` isInfixOf "(ruby (reunited ruby henry) :fail-first)"
      T.unpack (printDomain (problemDomain p)) `shouldSatisfy` isInfixOf ":attempt-text \"?a tries to tell ?b she loves him\""
      d <- either (fail . T.unpack) pure (parseDomain "d" (printDomain (problemDomain p)))
      d `shouldBe` problemDomain p
      parseProblem d "p" (printProblem p) `shouldBe` Right p

  describe "planning" $ do
    it "tries and fails while the Misbelief holds, realizes, then succeeds" $ do
      p <- turningPoint
      s <- firstStory p
      s `shouldBeValidFor` p
      storyLabels s `shouldBe` ["confess-love(ruby, henry)", "near-loss(ruby, henry)", "confess-love(ruby, henry)"]
      attemptLabels s `shouldBe` ["confess-love(ruby, henry)"]
      map (resolvedGoal s) (failedFrames s) `shouldBe` [reunited]
      T.lines (narrate p s)
        `shouldBe` [ "ruby believes love is dangerous."
                   , "ruby wants ruby is with henry."
                   , "ruby tries to tell henry she loves him, but ruby believes love is dangerous."
                   , "ruby almost loses henry."
                   , "ruby realizes it is not the case that love is dangerous."
                   , "ruby tells henry she loves him so that ruby is with henry."
                   ]
    it "orders every failed Frame entirely before its successful retry" $ do
      p <- failFirst <$> loadMisbelief
      let ss = stories 5 p
      length ss `shouldSatisfy` (> 1)
      mapM_
        ( \s -> do
            s `shouldBeValidFor` p
            let ok = and [O.before (planOrder s) x y | ff <- failedFrames s, sf <- IM.elems (planFrames s), isJust (frameFinal sf), frameGoal sf == frameGoal ff, x <- IS.toList (frameInterval ff), y <- IS.toList (frameInterval sf)]
            ok `shouldBe` True
        )
        ss
    it "never creates failed Frames without :fail-first" $ do
      p <- loadMisbelief
      let ss = stories 5 p
      length ss `shouldSatisfy` (> 1)
      mapM_ (\s -> (map frameAttempt (failedFrames s), planUnexecuted s) `shouldBe` ([], IS.empty)) ss
    it "prunes a second failed Frame for the same goal" $ do
      p <- turningPoint
      resultEnd (limited (failFirst p)) `shouldBe` Exhausted
    it "lets an unexecuted Step establish nothing" $ do
      p <- turningPoint
      s <- firstStory p
      let env = mkEnv p
          attempt = IS.findMin (planUnexecuted s)
          reopened = s {planLinks = Set.filter (\l -> linkTo l /= goalStepId) (planLinks s), planOpenConds = [(goalStepId, reunited)]}
          children = refine env reopened (OpenCondition goalStepId reunited)
      length children `shouldSatisfy` (> 0)
      [() | c <- children, l <- Set.toList (planLinks (childPlan c)), linkTo l == goalStepId, linkFrom l == attempt] `shouldBe` []
    it "needs a Frame only for the failed Frame's Character in a joint attempt" $ do
      s <- firstStory proposalProblem
      s `shouldBeValidFor` proposalProblem
      storyLabels s `shouldBe` ["marry(aladdin, jasmine)", "fall-for(jasmine, aladdin)", "marry(aladdin, jasmine)"]
      [frameCharacter f | f <- failedFrames s] `shouldBe` ["aladdin"]
      orphans s `shouldBe` []

  describe "misbelief-blocks" $ do
    let blockers p = map (T.concat . attemptLabels) (stories 4 p)
        preferring s = (\q -> q {problemPreferences = [Preference MisbeliefBlocks s]}) . elopeProblem
    it "lets something other than the Misbelief block the attempt by default" $ do
      p <- elopeProblem <$> turningPoint
      blockers p `shouldContain` ["elope(ruby, henry)"]
      [violations p s MisbeliefBlocks | s <- stories 4 p, attemptLabels s == ["elope(ruby, henry)"]] `shouldSatisfy` all (== 1)
    it "lets only the Misbelief block the attempt when hard" $ do
      p <- preferring Hard <$> turningPoint
      blockers p `shouldSatisfy` all (== "confess-love(ruby, henry)")
      length (blockers p) `shouldSatisfy` (> 0)
      mapM_ (`shouldBeValidFor` p) (stories 4 p)
    it "puts the Misbelief blocks first when soft" $ do
      plain <- elopeProblem <$> turningPoint
      p <- preferring (Soft 10) <$> turningPoint
      let misbeliefBlocked = length (filter (== "confess-love(ruby, henry)") (blockers plain))
      take misbeliefBlocked (blockers p) `shouldSatisfy` all (== "confess-love(ruby, henry)")
      blockers p `shouldContain` ["elope(ruby, henry)"]

  describe "validation and rendering" $ do
    it "checks failed Frames independently of the search" $ do
      p <- turningPoint
      s <- firstStory p
      let attempt = IS.findMin (planUnexecuted s)
          unblocked = s {planLinks = Set.filter ((/= attempt) . linkTo) (planLinks s)}
          executed = s {planUnexecuted = IS.empty}
          aimless = s {planFrames = IM.map (\f -> if isJust (frameAttempt f) then f {frameGoal = lit "loves" ["ruby", "henry"]} else f) (planFrames s)}
      validatePlan p unblocked `shouldContain` ["attempted step confess-love(ruby, henry) has 0 blocked preconditions, not 1"]
      validatePlan p executed `shouldContain` ["the unexecuted steps are not the attempted steps of failed frames"]
      validatePlan p aimless `shouldContain` ["frame ruby wants loves(ruby, henry)'s attempted step does not aim at its goal"]
    it "distinguishes failed Frames in story signatures" $ do
      p <- turningPoint
      s <- firstStory p
      let succeeded = s {planFrames = IM.map (\f -> f {frameAttempt = Nothing}) (planFrames s), planUnexecuted = IS.empty}
      storySignature succeeded `shouldNotBe` storySignature s
    it "renders attempts in the report, the scene cards and DOT" $ do
      p <- turningPoint
      s <- firstStory p
      T.unpack (renderPlan s) `shouldSatisfy` isInfixOf "confess-love(ruby, henry)  (attempt, blocked)"
      T.unpack (renderPlan s) `shouldSatisfy` isInfixOf "ruby wants reunited(ruby, henry) (fails)"
      T.unpack (renderCards p s) `shouldSatisfy` isInfixOf "Scene 1: ruby tries to tell henry she loves him, but ruby believes love is dangerous."
      T.length (planToDot p s) `shouldSatisfy` (> 0)
      elemIndex "near-loss(ruby, henry)" (storyLabels s) `shouldBe` Just 1
