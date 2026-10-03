-- | Intent planning (§4.3.3): Steps join the Intervals of the Frames they serve.
module IntentSpec (spec) where

import Data.IntMap.Strict qualified as IM
import Data.IntSet qualified as IS
import Data.List (nub)
import Data.Maybe (maybeToList)
import Data.Set qualified as Set
import Helpers
import IPOCL
import IPOCL.Domains.Bribe
import IPOCL.Domains.Tower
import IPOCL.Refine
import IPOCL.Search
import IPOCL.Syntax
import Test.Hspec

visitedPlans :: Problem -> Int -> [(Int, Maybe Int, Plan)]
visitedPlans p n =
  take n [(evNode e, evParent e, evPlan e) | e@Visited {} <- search (mkEnv p) defaultSearchConfig (initialPlan p)]

-- | The intent flaws Fig. 5 would propose for the refinement parent -> child:
-- condition 1 for a newly linked establisher, condition 2 for a new
-- Motivating step, and spreading activation after an adoption.
eagerCandidates :: Plan -> Plan -> [(StepId, FrameId)]
eagerCandidates parent child = nub (cond1 ++ cond2 ++ spreading)
  where
    frames = IM.elems (planFrames child)
    steps = planSteps child
    actorOf s c = maybe False (\st -> not (stepHappening st) && frameCharacter c `elem` stepActors st) (IM.lookup s steps)
    eligible s c = actorOf s c && not (IS.member s (frameInterval c))
    newLinks = Set.toList (planLinks child `Set.difference` planLinks parent)
    links = Set.toList (planLinks child)
    cond1 = [(linkFrom l, frameId c) | l <- newLinks, c <- frames, IS.member (linkTo l) (frameInterval c), eligible (linkFrom l) c]
    newMotivations =
      [ (m, f)
      | f <- frames
      , Just m <- [frameMotivator f]
      , m /= initStepId
      , maybe True ((/= Just m) . frameMotivator) (IM.lookup (frameId f) (planFrames parent))
      ]
    cond2 =
      [ (m, frameId c)
      | (m, ci) <- newMotivations
      , fin <- maybeToList (frameFinal ci)
      , l <- links
      , linkFrom l == fin
      , c <- frames
      , frameId c /= frameId ci
      , IS.member (linkTo l) (frameInterval c)
      , eligible m c
      ]
    adopted =
      [ (s, c)
      | c <- frames
      , Just old <- [IM.lookup (frameId c) (planFrames parent)]
      , s <- IS.toList (frameInterval c IS.\\ frameInterval old)
      ]
    spreading = [(linkFrom l, frameId c) | (s, c) <- adopted, l <- links, linkTo l == s, eligible (linkFrom l) c]

spec :: Spec
spec = do
  it "tells the bribe story with Coerce inside the Villain's Frame" $ do
    plan <- firstStory bribeProblem
    plan `shouldBeValidFor` bribeProblem
    storyLabels plan `shouldMatchList` ["coerce(villain, hero, has(villain, money))", "give(hero, villain, money)", "bribe(villain, president, money)"]
    let frames = frameSummary plan
    [(g, ss, m) | ("villain", g, ss, m) <- frames]
      `shouldBe` [("controls(villain, president)", ["coerce(villain, hero, has(villain, money))", "bribe(villain, president, money)"], "init")]
    [(g, ss, m) | ("hero", g, ss, m) <- frames]
      `shouldBe` [("has(villain, money)", ["give(hero, villain, money)"], "coerce(villain, hero, has(villain, money))")]
  it "proposes each Step-Frame pair at most once in a branch" $
    let ok (_, _, p) = let pend = planPendingIntent p in nub pend == pend && all (`Set.member` planProposedIntent p) pend
     in all ok (visitedPlans bribeProblem 3000 ++ visitedPlans motivatedTowerProblem 3000) `shouldBe` True
  it "proposes every intent flaw the paper's eager formulation would" $ do
    let check p = do
          let visited = visitedPlans p 3000
              byId = IM.fromList [(i, pl) | (i, _, pl) <- visited]
          sequence_
            [ [c | c <- eagerCandidates parent child, not (Set.member c (planProposedIntent child))] `shouldBe` []
            | (_, Just par, child) <- visited
            , Just parent <- [IM.lookup par byId]
            ]
    check bribeProblem
    check motivatedTowerProblem
