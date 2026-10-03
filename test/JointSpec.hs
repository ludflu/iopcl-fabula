-- | Joint actions and intentional threats (§4.3.1).
module JointSpec (spec) where

import Data.IntMap.Strict qualified as IM
import Data.IntSet qualified as IS
import Data.Set qualified as Set
import Data.Text qualified as T
import Helpers
import IPOCL
import IPOCL.Order
import IPOCL.Refine
import IPOCL.Search
import IPOCL.Syntax
import IPOCL.Validate
import SmallDomains
import Test.Hspec hiding (before)

-- | Every recorded frame ordering holds between all members of the two Frames.
frameOrdersHold :: Plan -> Bool
frameOrdersHold plan =
  and
    [ before (planOrder plan) x y
    | (a, b) <- Set.toList (planFrameOrder plan)
    , Just fa <- [IM.lookup a (planFrames plan)]
    , Just fb <- [IM.lookup b (planFrames plan)]
    , x <- IS.toList (frameInterval fa)
    , y <- IS.toList (frameInterval fb)
    ]

spec :: Spec
spec = do
  it "places a wedding in both the groom's and the bride's Intervals" $ do
    plan <- firstStory marriageProblem
    plan `shouldBeValidFor` marriageProblem
    [(c, g) | (c, g, ss, _) <- frameSummary plan, "marry(jafar, jasmine, castle)" `elem` ss]
      `shouldMatchList` [("jafar", "married-to(jafar, jasmine)"), ("jasmine", "married-to(jasmine, jafar)")]
  it "does not accept a Joint action that only one Actor intends" $ do
    plan <- firstStory marriageProblem
    let withoutBride = plan {planFrames = IM.filter ((/= Symbol "jasmine") . frameCharacter) (planFrames plan)}
    validatePlan marriageProblem withoutBride `shouldSatisfy` any ("not intentional for jasmine" `T.isInfixOf`)
  it "orders Frames with complementary Character goals one entirely before the other" $ do
    plan <- firstStory sleepyProblem
    plan `shouldBeValidFor` sleepyProblem
    Set.size (planFrameOrder plan) `shouldBe` 1
    frameOrdersHold plan `shouldBe` True
  it "keeps recorded frame orderings as Steps join ordered Frames" $
    let visited p = take 3000 [evPlan e | e@Visited {} <- search (mkEnv p) defaultSearchConfig (initialPlan p)]
     in all frameOrdersHold (visited sleepyProblem ++ visited marriageProblem) `shouldBe` True
