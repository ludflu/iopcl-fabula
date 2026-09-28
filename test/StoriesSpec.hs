module StoriesSpec (spec) where

import Data.List (nub)
import Data.Set qualified as Set
import IPOCL
import IPOCL.Domains.Bribe
import IPOCL.Signature
import IPOCL.Syntax (Problem)
import SmallDomains
import System.Exit (ExitCode (..))
import System.Process (readProcessWithExitCode)
import Test.Hspec
import Test.QuickCheck

firstSignature :: Int -> Problem -> Maybe StorySignature
firstSignature seed p = case resultStories (solvePure defaultSolveConfig {cfgSeed = seed} p) of
  s : _ -> Just (storySignature s)
  [] -> Nothing

spec :: Spec
spec = do
  describe "seeds" $ do
    it "give byte-identical output for the same seed" $ do
      let run = readProcessWithExitCode "narrative-planning" ["builtin", "bribe", "--seed", "7", "--count", "2"] ""
      (code, out1, _) <- run
      (_, out2, _) <- run
      code `shouldBe` ExitSuccess
      out1 `shouldBe` out2
    it "vary the first Story of a problem with several" $
      length (nub (map (`firstSignature` giftProblem) [0 .. 19])) `shouldSatisfy` (>= 2)
  describe "--count" $ do
    it "returns Stories with pairwise-distinct signatures" $ do
      let r = solvePure defaultSolveConfig {cfgCount = 3} giftProblem
          sigs = map storySignature (resultStories r)
      length sigs `shouldBe` 3
      nub sigs `shouldBe` sigs
    it "returns distinct Bribe Stories" $ do
      let r = solvePure defaultSolveConfig {cfgCount = 2} bribeProblem
          sigs = map storySignature (resultStories r)
      length sigs `shouldBe` 2
      nub sigs `shouldBe` sigs
  describe "duplicate detection" $ do
    it "never drops an item whose key has not been seen" $
      property $ \(seen :: [Int]) (xs :: [Int]) ->
        let (kept, seen') = dedupeBy id (Set.fromList seen) xs
            unseen = nub [x | x <- xs, x `notElem` seen]
         in kept === unseen .&&. seen' === Set.fromList (seen ++ xs)
    it "does not change whether small problems have a Story" $
      mapM_
        ( \p ->
            resultOutcome (solvePure defaultSolveConfig {cfgDedupe = True} p)
              `shouldBe` resultOutcome (solvePure defaultSolveConfig p)
        )
        [bribeProblem, marriageProblem, sleepyProblem, giftProblem]
