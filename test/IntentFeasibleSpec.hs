module IntentFeasibleSpec (spec) where

import Data.List (nub)
import Data.Set qualified as Set
import Helpers
import IPOCL
import IPOCL.Domains.Aladdin
import IPOCL.Domains.Bribe
import IPOCL.Domains.Tower
import IPOCL.IntentFeasible (intentAdoptForeverImpossible)
import IPOCL.Refine
import IPOCL.Search
import IPOCL.Syntax
import Test.Hspec

visitedEdges :: Problem -> Int -> [(Plan, Plan)]
visitedEdges p n =
  take n
    [ (parent, childPlan c)
    | parent <- [evPlan e | e@Visited {} <- search (mkEnv p) defaultSearchConfig (initialPlan p)]
    , Refined _ cs <- [expand (mkEnv p) parent]
    , c <- cs
    ]

newlyProposed :: Plan -> Plan -> [(StepId, FrameId)]
newlyProposed parent child =
  Set.toList (Set.difference (planProposedIntent child) (planProposedIntent parent))

spec :: Spec
spec = do
  describe "intent adopt forever impossible (ADR-0009)" $ do
    let problems = [towerProblem, motivatedTowerProblem, bribeProblem, aladdinProblem]
    it "never enqueues a forever-impossible pair on parent -> child edges" $
      mapM_
        ( \p ->
            mapM_
              ( \(parent, child) ->
                  let added = newlyProposed parent child
                      hopeless = filter (uncurry (intentAdoptForeverImpossible child)) added
                   in do
                        all (uncurry (intentAdoptForeverImpossible child)) hopeless `shouldBe` True
                        [ c | c <- hopeless, c `elem` planPendingIntent child ] `shouldBe` []
                        all (not . uncurry (intentAdoptForeverImpossible child)) (planPendingIntent child) `shouldBe` True
              )
              (visitedEdges p 1200)
        )
        problems
    it "matches unfiltered fresh0 on small sampled refine edges" $
      mapM_
        ( \p ->
            mapM_
              ( \(parent, child) -> do
                  let fresh0 = nub [c | c <- intentCandidates child, not (Set.member c (planProposedIntent parent))]
                   in Set.fromList (newlyProposed parent child) `shouldBe` Set.fromList fresh0
              )
              (visitedEdges p 600)
        )
        problems
    it "still finds motivated tower and bribe stories" $ do
      plan <- firstStory motivatedTowerProblem
      plan `shouldBeValidFor` motivatedTowerProblem
      plan' <- firstStory bribeProblem
      plan' `shouldBeValidFor` bribeProblem
