module BeamSpec (spec) where

import Data.Char (isDigit)
import Data.IntMap.Strict qualified as IM
import Data.List (nub)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Helpers
import IPOCL
import IPOCL.Beam
import IPOCL.Domains.Aladdin
import IPOCL.Domains.Bribe
import IPOCL.Domains.Tiny
import IPOCL.Domains.Tower
import IPOCL.Refine
import IPOCL.Search
import IPOCL.Signature
import IPOCL.Syntax (Problem)
import Test.Hspec

beam :: Int -> SolveConfig
beam k = defaultSolveConfig {cfgStrategy = Beam k, cfgMaxExpanded = Just 50000}

-- | The first @n@ events of a beam over a problem, with the default search config.
beamEvents :: Int -> SearchConfig -> Int -> Problem -> [SearchEvent]
beamEvents k cfg n p = take n (beamSearch k (mkEnv p) cfg (initialPlan p))

-- | (layer, node, parent) of each 'Visited' event, the layer read from its reason.
visits :: [SearchEvent] -> [(Int, Int, Maybe Int)]
visits evs = [(layerOf (evReason e), evNode e, evParent e) | e@Visited {} <- evs]
  where
    layerOf r = maybe (-1) (read . T.unpack . T.takeWhile isDigit) (T.stripPrefix "layer " r)

storyOf :: SolveConfig -> Problem -> IO Plan
storyOf cfg p = case resultStories (solvePure cfg p) of
  s : _ -> pure s
  [] -> expectationFailure "no story found" >> error "unreachable"

spec :: Spec
spec = do
  describe "stories" $ do
    it "finds valid Stories for Tiny, Bribe and motivated Tower" $
      mapM_ (\p -> storyOf (beam 100) p >>= (`shouldBeValidFor` p)) [tinyProblem, bribeProblem, motivatedTowerProblem]
    it "returns distinct valid Stories with --count" $ do
      let r = solvePure (beam 100) {cfgCount = 2} bribeProblem
      resultEnd r `shouldBe` Solved
      length (resultStories r) `shouldBe` 2
      length (nub (map storySignature (resultStories r))) `shouldBe` 2
      mapM_ (`shouldBeValidFor` bribeProblem) (resultStories r)
    it "finds a valid Story with --dedupe" $
      storyOf (beam 100) {cfgDedupe = True} bribeProblem >>= (`shouldBeValidFor` bribeProblem)

  describe "determinism" $
    it "gives the same Stories and counts for the same seed" $ do
      let run seed =
            let r = solvePure (beam 5) {cfgCount = 2, cfgSeed = seed} bribeProblem
             in (resultEnd r, map storySignature (resultStories r), resultExpanded r, resultGenerated r)
      run 7 `shouldBe` run 7
      run 0 `shouldBe` run 0

  describe "incompleteness" $ do
    it "gives up with LimitHit when a width-1 beam follows a dead end" $ do
      resultEnd (solvePure defaultSolveConfig bribeProblem) `shouldBe` Solved
      let r = solvePure (beam 1) bribeProblem
      resultEnd r `shouldBe` LimitHit
      resultStories r `shouldSatisfy` null
    it "reports LimitHit, never Exhausted, on unmotivated Tower" $
      mapM_ (\k -> resultEnd (solvePure (beam k) towerProblem) `shouldBe` LimitHit) [1, 100]
    it "ends its stream with GaveUp when a layer is empty" $
      map isGaveUp (beamEvents 1 defaultSearchConfig 10000 bribeProblem) `shouldEndWith` [True]
    it "is lazy, so a node limit stops it" $ do
      let r = solvePure (beam 10000) {cfgMaxExpanded = Just 50} aladdinProblem
      (resultEnd r, resultExpanded r) `shouldBe` (LimitHit, 50)

  describe "layers" $ do
    it "never holds more than the width in a layer, and fills it" $ do
      let k = 3
          sizes = Map.fromListWith (+) [(l, 1 :: Int) | (l, _, _) <- visits (beamEvents k defaultSearchConfig 300 motivatedTowerProblem)]
      Map.lookup 0 sizes `shouldBe` Just 1
      maximum sizes `shouldBe` k
    it "numbers nodes uniquely, with each parent visited in the layer before" $ do
      let vs = visits (beamEvents 4 defaultSearchConfig 300 bribeProblem)
          layerOfNode = IM.fromList [(i, l) | (l, i, _) <- vs]
      length (nub [i | (_, i, _) <- vs]) `shouldBe` length vs
      [(l, i) | (l, i, Just par) <- vs, IM.lookup par layerOfNode /= Just (l - 1)] `shouldBe` []
      [i | (l, i, Nothing) <- vs, l /= 0] `shouldBe` []
    it "drops repeated signatures across the run with --dedupe" $ do
      let cfg = defaultSearchConfig {scSignature = Just planSignature}
          sigs = [planSignature (evPlan e) | e@Visited {} <- beamEvents 10 cfg 500 aladdinProblem]
      length (nub sigs) `shouldBe` length sigs
  where
    isGaveUp = \case
      GaveUp -> True
      _ -> False
