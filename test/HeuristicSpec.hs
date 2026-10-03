module HeuristicSpec (spec) where

import Control.Monad (forM_)
import FetchDomain
import GHC.Clock (getMonotonicTime)
import Helpers
import IPOCL
import IPOCL.Bindings
import IPOCL.Domains.Aladdin
import IPOCL.Domains.Bribe
import IPOCL.Domains.Tiny
import IPOCL.Domains.Tower
import IPOCL.Ground
import IPOCL.Heuristic
import IPOCL.Syntax
import SmallDomains
import Test.Hspec

-- | Tiny plus an action that needs wings nobody can grow.
wingedProblem :: Problem
wingedProblem =
  tinyProblem
    { problemDomain =
        (problemDomain tinyProblem)
          { domainSchemas =
              domainSchemas (problemDomain tinyProblem)
                ++ [ (schema "fly" ["?who"])
                       { schemaActors = [Var "who" 0]
                       , schemaConstraints = [atom "character" ["?who"]]
                       , schemaPrecondition = [PLit (lit "winged" ["?who"])]
                       , schemaEffect = [lit "awake" ["?who"]]
                       }
                   ]
          }
    }

smallProblems :: [(String, Problem)]
smallProblems =
  [ ("tiny", tinyProblem)
  , ("tower", towerProblem)
  , ("motivated tower", motivatedTowerProblem)
  , ("fetch", fetchProblem)
  , ("sleepy", sleepyProblem)
  , ("bribe", bribeProblem)
  ]

spec :: Spec
spec = do
  describe "reachability" $ do
    it "reaches facts that need a chain of several actions" $ do
      let r = reachability (problemInit motivatedTowerProblem) (groundActions motivatedTowerProblem)
      literalCost r emptyBindings (intends "knight" (Right (nlit "alive" ["king"]))) `shouldBe` Just 2
    it "drops ground actions whose preconditions can never hold" $ do
      let r = reachability (problemInit wingedProblem) (groundActions wingedProblem)
      map groundActionLabel (reachableActions r) `shouldBe` ["wake-up(hero)"]
    forM_ [("tiny", tinyProblem), ("tower", towerProblem), ("bribe", bribeProblem), ("aladdin", aladdinProblem)] $ \(name, p) ->
      it ("memoises the same costs as the direct computation on " <> name) $ do
        let r = reachability (problemInit p) (groundActions p)
            gas = reachableActions r
        [l | l <- wantedLiterals gas, literalCost r emptyBindings l /= uncachedLiteralCost r l] `shouldBe` []
        [a | g <- gas, a <- gaActors g, intentionCost r a /= uncachedIntentionCost r a] `shouldBe` []
        [l | l <- problemOutcome p, literalCost r emptyBindings l /= uncachedLiteralCost r l] `shouldBe` []
  describe "search" $ do
    it "reports statistics when a limit is hit" $ do
      let r = solvePure defaultSolveConfig {cfgMaxExpanded = Just 100} aladdinProblem
      resultEnd r `shouldBe` LimitHit
      resultExpanded r `shouldBe` 100
    forM_ smallProblems $ \(name, p) ->
      it ("agrees with blind search about whether " <> name <> " has a story") $ do
        let informed = solvePure defaultSolveConfig p
            blind = solvePure defaultSolveConfig {cfgHeuristic = Blind} p
        resultEnd informed `shouldBe` resultEnd blind
        mapM_ (`shouldBeValidFor` p) (resultStories informed ++ resultStories blind)
  describe "Level A" $
    forM_ [("motivated tower", motivatedTowerProblem), ("bribe", bribeProblem), ("reduced Aladdin", marriageProblem)] $ \(name, p) ->
      it ("tells the " <> name <> " story in under 10 seconds") $ do
        start <- getMonotonicTime
        r <- solve defaultSolveConfig {cfgTimeout = Just 10} p
        resultEnd r `shouldBe` Solved
        end <- getMonotonicTime
        (end - start) `shouldSatisfy` (< 10)
