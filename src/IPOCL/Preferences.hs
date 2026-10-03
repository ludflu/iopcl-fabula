-- | Author preferences: hard ones prune plans, soft ones add to the heuristic.
module IPOCL.Preferences
  ( violations
  , hardViolated
  , finalViolated
  , softPenalty
  , isRelevanceRule
  , protagonistArc
  ) where

import Data.IntMap.Strict qualified as IM
import Data.IntSet (IntSet)
import Data.IntSet qualified as IS
import Data.Maybe (isJust)
import Data.Set qualified as Set
import IPOCL.Bindings
import IPOCL.Ground
import IPOCL.Linearize
import IPOCL.Plan
import IPOCL.Syntax

-- | How many times a plan breaks a rule. For every rule except the relevance
-- rules, these are violations no further refinement can undo, so pruning on
-- them is safe. Relevance violations can disappear when a Step is reused as
-- an establisher and gains a link (spec §4.12).
violations :: Problem -> Plan -> PreferenceRule -> Int
violations p plan = \case
  AllowGoals c allowed -> count (\g -> not (any (isJust . unifyLiterals b g) allowed)) (goalsOf c)
  ForbidGoal c l -> count (== l) (goalsOf c)
  MaxFrames c n -> max 0 (length (framesOf plan c) - n)
  NoRepeatSteps -> length groundSteps - Set.size (Set.fromList groundSteps)
  ThirdRail -> count (not . serves . stepId) (actionSteps plan)
  ServesProtagonist c -> count (not . maybe True serves . frameEnd) (framesOf plan c)
  MaxBackstory n -> max 0 (Set.size (planBackstory plan) - n)
  MisbeliefBlocks -> count (not . blockedByMisbelief) (concatMap attempts (maybe [] (framesOf plan) (problemProtagonist p)))
  RealizationBeforeDesireProgress -> realizationBeforeDesireViolations p plan
  where
    b = planBindings plan
    goalsOf c = map (resolvedGoal plan) (framesOf plan c)
    count f = length . filter f
    groundSteps =
      [ (gaIndex g, args)
      | s <- actionSteps plan
      , not (isUnexecuted plan (stepId s))
      , let args = map (resolve b) (stepArgs s)
      , all (null . termVars) args
      , Just g <- [stepAction s]
      ]
    -- The link holding an attempted Step's blocked precondition false.
    attempts f =
      [ l
      | Just a <- [frameAttempt f]
      , Just st <- [IM.lookup a (planSteps plan)]
      , l <- Set.toList (planLinks plan)
      , linkTo l == a
      , resolveLiteral b (negateLit (linkCond l)) `elem` map (resolveLiteral b) (stepPre st)
      ]
    blockedByMisbelief l =
      linkFrom l == initStepId && litPositive (linkCond l) && litAtom (resolveLiteral b (linkCond l)) `elem` ownMisbeliefs
    ownMisbeliefs = [m | Just c <- [problemProtagonist p], m <- problemMisbeliefs p, take 1 (atomArgs m) == [TSym c]]
    arc = protagonistArc p plan
    reachesArc = reaching plan arc
    serves s = IS.member s reachesArc

-- | Rules whose violations can go down later, so they are never pruned on
-- before the goal test.
isRelevanceRule :: PreferenceRule -> Bool
isRelevanceRule = \case
  ThirdRail -> True
  ServesProtagonist _ -> True
  RealizationBeforeDesireProgress -> True
  _ -> False

-- | Prunes a partial plan; relevance rules wait for 'finalViolated'.
hardViolated :: Problem -> [Preference] -> Plan -> Bool
hardViolated p prefs plan = or [violations p plan r > 0 | Preference r Hard <- prefs, not (isRelevanceRule r)]

-- | Every hard rule, for a plan with no flaws left.
finalViolated :: Problem -> [Preference] -> Plan -> Bool
finalViolated p prefs plan = or [violations p plan r > 0 | Preference r Hard <- prefs]

softPenalty :: Problem -> [Preference] -> Plan -> Int
softPenalty p prefs plan = sum [w * violations p plan r | Preference r (Soft w) <- prefs]

-- | The Steps in the Protagonist's Intervals, the Motivating steps of the
-- Protagonist's Frames, and every Realization of a Protagonist Misbelief.
protagonistArc :: Problem -> Plan -> IntSet
protagonistArc p plan = case problemProtagonist p of
  Nothing -> IS.empty
  Just c ->
    let frames = framesOf plan c
        own = [m | m <- problemMisbeliefs p, take 1 (atomArgs m) == [TSym c]]
        realizes s = not (isUnexecuted plan (stepId s)) && any (\e -> not (litPositive e) && litAtom (resolveLiteral (planBindings plan) e) `elem` own) (stepEff s)
     in IS.unions (map frameInterval frames)
          <> IS.fromList [m | f <- frames, Just m <- [frameMotivator f], m /= initStepId]
          <> IS.fromList [stepId s | s <- actionSteps plan, realizes s]

-- | Steps with a path to the target set (members included), following causal
-- links and motivation links from a Motivating step to its Interval.
reaching :: Plan -> IntSet -> IntSet
reaching plan = go
  where
    edges =
      [(linkFrom l, linkTo l) | l <- Set.toList (planLinks plan)]
        ++ [(m, s) | f <- IM.elems (planFrames plan), Just m <- [frameMotivator f], s <- IS.toList (frameInterval f)]
    preds = IM.fromListWith (<>) [(t, IS.singleton s) | (s, t) <- edges]
    go seen =
      let next = IS.unions [IM.findWithDefault IS.empty t preds | t <- IS.toList seen]
          seen' = seen <> next
       in if IS.size seen' == IS.size seen then seen else go seen'

realizationBeforeDesireViolations :: Problem -> Plan -> Int
realizationBeforeDesireViolations p plan =
  case (problemProtagonist p, problemDesire p) of
    (Nothing, _) -> 0
    (_, Nothing) -> 0
    (Just c, Just desireLit) ->
      let b = planBindings plan
          desire = resolveLiteral b desireLit
          ownMisbeliefs = [m | m <- problemMisbeliefs p, take 1 (atomArgs m) == [TSym c]]
          unifiesDesire l = isJust (unifyLiterals b (resolveLiteral b l) desire)
          realizes s =
            not (isUnexecuted plan (stepId s))
              && any (\e -> not (litPositive e) && litAtom (resolveLiteral b e) `elem` ownMisbeliefs) (stepEff s)
          advancesDesire s
            | isUnexecuted plan (stepId s) = False
            | any (\f -> frameCharacter f == c && frameFinal f == Just (stepId s) && unifiesDesire (resolvedGoal plan f)) (framesOf plan c) = True
            | c `notElem` stepActors s = False
            | otherwise =
                any (\e -> litPositive e && unifiesDesire e) (map (resolveLiteral b) (stepEff s))
                  || any (\l -> linkFrom l == stepId s && litPositive (linkCond l) && unifiesDesire (linkCond l)) (Set.toList (planLinks plan))
          walk _ n [] = n
          walk seenRealization n (s : ss)
            | realizes s = walk True n ss
            | not seenRealization && advancesDesire s = walk seenRealization (n + 1) ss
            | otherwise = walk seenRealization n ss
       in walk False 0 (linearize plan)
