module MctsSpec (spec) where

import Data.IntSet qualified as IS
import Data.List (group, isInfixOf, nub)
import Data.Text qualified as T
import Helpers
import IPOCL
import IPOCL.Domains.Aladdin
import IPOCL.Domains.Bribe
import IPOCL.Domains.Tiny
import IPOCL.Domains.Tower
import IPOCL.Mcts
import IPOCL.Refine
import IPOCL.Search
import IPOCL.Signature
import IPOCL.Syntax (Problem)
import Test.Hspec

mctsWith :: Int -> Int -> Int -> Problem -> Result
mctsWith seed count limit =
  solvePure defaultSolveConfig {cfgStrategy = Mcts defaultMctsParams, cfgSeed = seed, cfgCount = count, cfgMaxExpanded = Just limit}

-- | The raw event stream, with the given rollout cut-off.
streamWith :: Int -> Int -> Problem -> [SearchEvent]
streamWith seed depth p =
  mctsSearch defaultMctsParams {mctsRolloutDepth = depth} (mkEnv p) defaultSearchConfig {scSeed = seed} (initialPlan p)

visits :: [SearchEvent] -> [SearchEvent]
visits evs = [e | e@Visited {} <- evs]

isRollout :: SearchEvent -> Bool
isRollout e = "rollout" `isInfixOf` T.unpack (evReason e)

-- | Every node number is new, and every parent was visited earlier.
wellNumbered :: [SearchEvent] -> Bool
wellNumbered = go IS.empty
  where
    go seen = \case
      [] -> True
      e : rest ->
        IS.notMember (evNode e) seen
          && maybe (IS.null seen) (`IS.member` seen) (evParent e)
          && go (IS.insert (evNode e) seen) rest

spec :: Spec
spec = do
  it "finds Stories that pass validation on Tiny, Bribe and motivated Tower" $
    mapM_
      ( \p -> case resultStories (mctsWith 0 1 8000 p) of
          s : _ -> s `shouldBeValidFor` p
          [] -> expectationFailure "no story found"
      )
      [tinyProblem, bribeProblem, motivatedTowerProblem]
  it "gives the same Stories and counts for the same seed" $ do
    let summary r = (resultEnd r, resultExpanded r, resultGenerated r, map storyLabels (resultStories r))
        r = mctsWith 7 2 8000 bribeProblem
    length (resultStories r) `shouldBe` 2
    summary r `shouldBe` summary (mctsWith 7 2 8000 bribeProblem)
  it "explores differently with a different seed" $ do
    let reasons seed = map evReason (take 2000 (visits (streamWith seed 150 bribeProblem)))
    reasons 0 `shouldNotBe` reasons 1
  it "ends Exhausted on unmotivated Tower because the root is exhausted" $
    resultEnd (mctsWith 0 1 8000 towerProblem) `shouldBe` Exhausted
  it "ends the stream once the root is exhausted, after finding every Story" $ do
    let r = mctsWith 0 50 8000 motivatedTowerProblem
    resultEnd r `shouldBe` Solved
    resultExpanded r `shouldSatisfy` (< 8000)
    mapM_ (`shouldBeValidFor` motivatedTowerProblem) (resultStories r)
  it "returns distinct Stories for count 3 on Bribe, as many as exist" $ do
    let stories = resultStories (mctsWith 0 3 8000 bribeProblem)
    length stories `shouldBe` 2
    length (nub (map storySignature stories)) `shouldBe` 2
    mapM_ (`shouldBeValidFor` bribeProblem) stories
  it "is lazy and unbounded until the root is exhausted" $
    length (take 3000 (streamWith 0 150 aladdinProblem)) `shouldBe` 3000
  it "numbers nodes uniquely and points each at a visited parent" $
    wellNumbered (visits (take 3000 (streamWith 0 150 aladdinProblem))) `shouldBe` True
  it "marks rollout steps and cuts rollouts off at the configured depth" $ do
    let evs = visits (take 2000 (streamWith 0 3 bribeProblem))
    any isRollout evs `shouldBe` True
    maximum (0 : [length run | run@(True : _) <- group (map isRollout evs)]) `shouldSatisfy` (<= 3)
    any isRollout (visits (take 500 (streamWith 0 0 bribeProblem))) `shouldBe` False
  it "emits complete plans reached in the tree and in rollouts" $ do
    let evs = take 5000 (streamWith 0 150 motivatedTowerProblem)
        found = [(v, f) | (v, f@FoundSolution {}) <- zip evs (drop 1 evs)]
    length found `shouldBe` length [() | FoundSolution {} <- evs]
    all (\(v, f) -> evNode v == evNode f && isSolution (evPlan f)) found `shouldBe` True
    any (isRollout . fst) found `shouldBe` True
    all (isRollout . fst) found `shouldBe` False
  where
    isSolution plan = case expand (mkEnv motivatedTowerProblem) plan of
      Solution -> True
      _ -> False
