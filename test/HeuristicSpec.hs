module HeuristicSpec (spec) where

import Control.Monad (forM_)
import Data.IntMap.Strict qualified as IM
import Data.IntSet qualified as IS
import Data.Maybe (fromMaybe)
import FetchDomain
import GHC.Clock (getMonotonicTime)
import Helpers
import IPOCL
import IPOCL.Bindings
import IPOCL.Domains.Aladdin
import IPOCL.Domains.Bribe
import IPOCL.Domains.Tiny
import IPOCL.Domains.Tower
import IPOCL.Ground (GroundAction, gaArgs, gaActors, gaEff, gaHappening, gaPre, groundActionLabel, groundActions, instantiateLiteral, instantiateTerm)
import IPOCL.Heuristic
import IPOCL.IntentFeasible (intentAdoptForeverImpossible)
import IPOCL.Order (addOrder)
import IPOCL.Plan (Frame (..), Step (..), goalStepId, initStepId)
import IPOCL.Refine (mkEnv)
import IPOCL.Search (SearchEvent (Visited), defaultSearchConfig, evPlan, search)
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

insertWakeStep :: GroundAction -> Plan -> Plan
insertWakeStep g p =
  let k = planNextStep p
      st =
        Step
          { stepId = k
          , stepAction = Just g
          , stepArgs = map (instantiateTerm k) (gaArgs g)
          , stepActors = gaActors g
          , stepHappening = gaHappening g
          , stepPre = map (instantiateLiteral k) (gaPre g)
          , stepEff = map (instantiateLiteral k) (gaEff g)
          }
      o = fromMaybe (planOrder p) (addOrder initStepId k (planOrder p) >>= addOrder k goalStepId)
   in p
        { planSteps = IM.insert k st (planSteps p)
        , planOrder = o
        , planOpenConds = [(k, q) | q <- stepPre st] ++ planOpenConds p
        , planNextStep = k + 1
        }

-- | Pending (2,0): adopt needs motivator 3 before step 2, but order can forbid it.
craftHopelessPendingIntentPlans :: (Plan, Plan)
craftHopelessPendingIntentPlans =
  let p0 = initialPlan tinyProblem
      g = head (groundActions tinyProblem)
      body = insertWakeStep g . insertWakeStep g . insertWakeStep g $ p0
      frame0 =
        Frame
          { frameId = 0
          , frameCharacter = "hero"
          , frameGoal = intends "hero" (Right (lit "awake" ["hero"]))
          , frameFinal = Just 4
          , frameInterval = IS.fromList [4]
          , frameMotivator = Just 3
          , frameAttempt = Nothing
          }
      withPending pl =
        pl
          { planFrames = IM.insert 0 frame0 (planFrames pl)
          , planPendingIntent = [(2, 0)]
          , planNextFrame = 1
          }
      hopeless =
        withPending $
          case addOrder 2 3 (planOrder body) of
            Nothing -> error "hopeless order"
            Just o -> body {planOrder = o}
      ok =
        withPending $
          case addOrder 3 2 (planOrder body) of
            Nothing -> error "ok order"
            Just o -> body {planOrder = o}
   in (hopeless, ok)

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
  describe "hopeless intent surcharge" $ do
    it "inflates additive h for hopeless pending intents on a crafted Tiny plan" $ do
      let r = problemReachability tinyProblem
          (hopeless, ok) = craftHopelessPendingIntentPlans
      intentAdoptForeverImpossible hopeless 2 0 `shouldBe` True
      intentAdoptForeverImpossible ok 2 0 `shouldBe` False
      case (additiveHeuristic r hopeless, additiveHeuristic r ok) of
        (Just hH, Just hO) -> (hH - hO) `shouldBe` (hopelessIntentCost - 1)
        _ -> expectationFailure "additiveHeuristic returned Nothing"
    it "matches legacy pending count when every pending pair can still adopt" $ do
      let env = mkEnv tinyProblem
          visited = take 800 [evPlan e | e@Visited {} <- search env defaultSearchConfig (initialPlan tinyProblem)]
      forM_ visited $ \plan ->
        let pending = planPendingIntent plan
            legacy = length pending
            charged =
              sum
                [ if intentAdoptForeverImpossible plan s c then hopelessIntentCost else 1
                | (s, c) <- pending
                ]
         in charged `shouldBe` legacy
