module RelevanceSpec (spec) where

import Data.IntMap.Strict qualified as IM
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Helpers
import IPOCL
import IPOCL.DomainCheck
import IPOCL.Lint
import IPOCL.Parser
import IPOCL.Preferences
import IPOCL.Refine
import IPOCL.Syntax
import Test.Hspec

-- | Ruby's misbelief story, plus a hungry dog the Outcome needs fed. Henry
-- wants to feed it, which is irrelevant to Ruby; Ruby can feed it too once
-- she notices it is hungry.
dogProblem :: IO Problem
dogProblem = do
  p <-
    loadProblem "domains/misbelief.ipocl" "domains/misbelief-problem.ipocl"
      >>= either (\e -> expectationFailure (T.unpack e) >> error "unreachable") pure
  let d = problemDomain p
      feed =
        (schema "feed" ["?a", "?d"])
          { schemaActors = [Var "a" 0]
          , schemaConstraints = [atom "character" ["?a"], atom "pet" ["?d"]]
          , schemaEffect = [lit "fed" ["?d"]]
          }
      notice =
        (schema "notice-hunger" ["?a", "?d"])
          { schemaHappening = True
          , schemaConstraints = [atom "character" ["?a"], atom "pet" ["?d"]]
          , schemaEffect = [intends "?a" (Right (lit "fed" ["?d"]))]
          }
  pure
    p
      { problemDomain = d {domainSchemas = filter ((/= "rescue") . schemaName) (domainSchemas d) ++ [feed, notice]}
      , problemInit = problemInit p <> Set.fromList [atom "pet" ["rex"], litAtom (intends "henry" (Right (lit "fed" ["rex"])))]
      , problemOutcome = problemOutcome p ++ [lit "fed" ["rex"]]
      }

withPrefs :: [Preference] -> Problem -> Problem
withPrefs prefs p = p {problemPreferences = prefs}

hard, soft :: PreferenceRule -> Preference
hard r = Preference r Hard
soft r = Preference r (Soft 10)

henryFeeds, ruby'sStory :: [Text]
henryFeeds = ["feed(henry, rex)", "near-loss(ruby, henry)", "confess-love(ruby, henry)"]
ruby'sStory = ["notice-hunger(ruby, rex)", "feed(ruby, rex)", "near-loss(ruby, henry)", "confess-love(ruby, henry)"]

spec :: Spec
spec = describe "third-rail relevance" $ do
  it "finds the irrelevant side plot without preferences" $ do
    p <- dogProblem
    s <- firstStory p
    storyLabels s `shouldMatchList` henryFeeds
    violations p s ThirdRail `shouldBe` 1
    violations p s (ServesProtagonist "henry") `shouldBe` 1

  it "drops the side plot under a hard third-rail" $ do
    p <- withPrefs [hard ThirdRail] <$> dogProblem
    s <- firstStory p
    storyLabels s `shouldMatchList` ruby'sStory
    s `shouldBeValidFor` p
    violations p s ThirdRail `shouldBe` 0

  it "never prunes a partial plan under a hard third-rail" $ do
    p <- withPrefs [hard ThirdRail] <$> dogProblem
    let env = mkEnv p
        start = initialPlan p
        partial =
          [ childPlan c
          | c <- refine env start (OpenCondition goalStepId (lit "fed" ["rex"]))
          , "feed(henry, rex)" `elem` storyLabels (childPlan c)
          ]
    length partial `shouldSatisfy` (> 0)
    mapM_
      ( \pl -> do
          violations p pl ThirdRail `shouldBe` 1
          envPrune env pl `shouldBe` False
          case expand env pl of
            Refined _ cs -> length cs `shouldSatisfy` (> 0)
            _ -> expectationFailure "expected the partial plan to be expanded"
      )
      partial

  it "rejects a complete plan at the goal test" $ do
    plain <- dogProblem
    s <- firstStory plain
    let p = withPrefs [hard ThirdRail] plain
        env = mkEnv p
    case expand env s of
      DeadEnd Nothing -> pure ()
      _ -> expectationFailure "expected a dead end"

  it "keeps only Frames of a Character that serve the Protagonist under a hard serves-protagonist" $ do
    p <- withPrefs [hard (ServesProtagonist "henry")] <$> dogProblem
    s <- firstStory p
    storyLabels s `shouldMatchList` ruby'sStory
    violations p s (ServesProtagonist "henry") `shouldBe` 0

  it "charges a soft serves-protagonist for each Frame that does not serve" $ do
    plain <- dogProblem
    s <- firstStory plain
    softPenalty plain [soft (ServesProtagonist "henry")] s `shouldBe` 10
    softPenalty plain [soft (ServesProtagonist "ruby")] s `shouldBe` 0
    let p = withPrefs [soft (ServesProtagonist "henry")] plain
    s' <- firstStory p
    storyLabels s' `shouldMatchList` ruby'sStory

  it "needs a Protagonist" $ do
    p <- dogProblem
    checkProblem (withPrefs [soft ThirdRail] p {problemProtagonist = Nothing, problemDesire = Nothing})
      `shouldBe` ["preference third-rail needs a protagonist"]
    checkProblem (withPrefs [soft (ServesProtagonist "henry")] p) `shouldBe` []

  describe "internal-change lint" $ do
    it "is quiet when every internal change leads to action" $ do
      p <- withPrefs [hard ThirdRail] <$> dogProblem
      s <- firstStory p
      planWarnings p s `shouldBe` []
    it "warns about a Realization that leads to no action" $ do
      p <- dogProblem
      s <- firstStory p
      let cut = s {planLinks = Set.filter (not . fromRealization s) (planLinks s)}
      planWarnings p cut `shouldBe` ["near-loss(ruby, henry): the internal change of ruby leads to no action by ruby"]
  where
    fromRealization s l = maybe False ((== "near-loss(ruby, henry)") . stepLabel s) (IM.lookup (linkFrom l) (planSteps s))
