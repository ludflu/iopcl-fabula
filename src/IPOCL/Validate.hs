-- | An independent check that a plan is complete (Defs. 3 and 6) and that one
-- of its linearisations actually reaches the Outcome from the initial state.
module IPOCL.Validate
  ( validatePlan
  ) where

import Data.IntMap.Strict qualified as IM
import Data.IntSet qualified as IS
import Data.Maybe (isJust, isNothing)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import IPOCL.Bindings
import IPOCL.Linearize
import IPOCL.Order
import IPOCL.Plan
import IPOCL.Pretty
import IPOCL.Syntax

-- | Every violation found; an empty list means the plan is valid.
validatePlan :: Problem -> Plan -> [Text]
validatePlan prob plan =
  concat
    [ backstoryViolations
    , attemptViolations
    , supportViolations
    , threatViolations
    , frameViolations
    , orphanViolations
    , requiredViolations
    , simulate prob plan
    ]
  where
    b = planBindings plan
    o = planOrder plan
    steps = planSteps plan
    lbl s = maybe (T.pack (show s)) (stepLabel plan) (IM.lookup s steps)
    res = resolveLiteral b
    initAtoms = problemInit prob <> planBackstory plan
    attempted = IS.fromList [a | f <- IM.elems (planFrames plan), Just a <- [frameAttempt f]]
    effectsOf s = maybe [] (map res . stepEff) (IM.lookup s steps)
    provides s l
      | s == initStepId = if litPositive l then Set.member (litAtom l) initAtoms else not (Set.member (litAtom l) initAtoms)
      | otherwise = l `elem` effectsOf s

    backstoryViolations =
      [ "backstory " <> prettyAtom a <> " is not possible backstory"
      | a <- Set.toList (planBackstory plan)
      , a `notElem` problemBackstory prob
      ]
        ++ [ "closed-world support for unknown backstory " <> prettyLiteral (res (linkCond l))
           | l <- Set.toList (planLinks plan)
           , linkFrom l == initStepId
           , not (litPositive (linkCond l))
           , litAtom (res (linkCond l)) `elem` problemBackstory prob
           , not (Set.member (litAtom (res (linkCond l))) (planBackstory plan))
           ]
    linkedTo s q = any (\l -> linkTo l == s && res (linkCond l) == res q) (planLinks plan)
    attemptViolations =
      [ "the unexecuted steps are not the attempted steps of failed frames" | attempted /= planUnexecuted plan ]
        ++ [ "attempted step " <> lbl a <> " has " <> T.pack (show n) <> " blocked preconditions, not 1"
           | a <- IS.toList attempted
           , let n = length [q | q <- pres a, linkedTo a (negateLit q)]
           , n /= 1
           ]
        ++ [ "attempted step " <> lbl (linkFrom l) <> " establishes " <> prettyLiteral (res (linkCond l))
           | l <- Set.toList (planLinks plan)
           , IS.member (linkFrom l) attempted
           ]
    pres s = maybe [] stepPre (IM.lookup s steps)
    supportViolations =
      [ "precondition " <> prettyLiteral (res q) <> " of " <> lbl (stepId s) <> " has no causal link"
      | s <- planStepList plan
      , q <- stepPre s
      , not (linkedTo (stepId s) q)
      , not (IS.member (stepId s) attempted && linkedTo (stepId s) (negateLit q))
      ]
        ++ [ "causal link " <> lbl (linkFrom l) <> " -> " <> lbl (linkTo l) <> " is broken"
           | l <- Set.toList (planLinks plan)
           , not (before o (linkFrom l) (linkTo l)) || not (provides (linkFrom l) (res (linkCond l)))
           ]

    threatViolations =
      [ lbl (stepId t) <> " threatens " <> prettyLiteral (res (linkCond l)) <> " from " <> lbl (linkFrom l) <> " to " <> lbl (linkTo l)
      | l <- Set.toList (planLinks plan)
      , t <- planStepList plan
      , not (IS.member (stepId t) attempted)
      , stepId t `notElem` [linkFrom l, linkTo l]
      , possiblyBefore o (linkFrom l) (stepId t)
      , possiblyBefore o (stepId t) (linkTo l)
      , any (\e -> isJust (unifyLiterals b e (negateLit (linkCond l)))) (stepEff t)
      ]

    frameViolations = concatMap frameProblems (IM.elems (planFrames plan))
    frameProblems f =
      let name = "frame " <> symbolText (frameCharacter f) <> " wants " <> prettyLiteral (res (frameGoal f))
          members = IS.toList (frameInterval f)
       in [name <> " has a non-Actor member " <> lbl s | s <- members, not (isActor s (frameCharacter f))]
            ++ [name <> " contains the happening " <> lbl s | s <- members, maybe False stepHappening (IM.lookup s steps)]
            ++ case frameFinal f of
              Nothing -> case frameAttempt f of
                Nothing -> [name <> " has no final step"]
                Just a ->
                  [name <> "'s attempted step does not aim at its goal" | res (frameGoal f) `notElem` effectsOf a]
                    ++ [name <> "'s attempted step is not in its interval" | not (IS.member a (frameInterval f))]
                    ++ [name <> ": " <> lbl s <> " does not precede the attempted step" | s <- members, s /= a, not (before o s a)]
              Just fin ->
                [name <> " has both a final and an attempted step" | isJust (frameAttempt f)]
                  ++ [name <> "'s final step does not achieve its goal" | res (frameGoal f) `notElem` effectsOf fin]
                  ++ [name <> "'s final step is not in its interval" | not (IS.member fin (frameInterval f))]
                  ++ [name <> ": " <> lbl s <> " does not precede the final step" | s <- members, s /= fin, not (before o s fin)]
            ++ case frameMotivator f of
              Nothing -> [name <> " has no motivating step"]
              Just m ->
                [name <> " is not motivated by " <> lbl m | not (provides m (res (frameIntention f)))]
                  ++ [name <> ": motivating step does not precede " <> lbl s | s <- members, not (before o m s)]
    isActor s c = maybe False ((c `elem`) . stepActors) (IM.lookup s steps)

    requiredViolations =
      [ "required frame " <> symbolText c <> " wants " <> prettyLiteral g <> " is not in the story"
      | RequiredFrame c g _ <- requiredFrames prob
      , not (any (fulfilled c g) (planStepList plan))
      ]
        ++ [ "required frame " <> symbolText c <> " wants " <> prettyLiteral g <> " has no failed frame before it"
           | RequiredFrame c g True <- requiredFrames prob
           , not (any (failsFirst c g) (IM.elems (planFrames plan)))
           ]
    failsFirst c g ff =
      frameCharacter ff == c
        && isNothing (frameFinal ff)
        && isJust (frameAttempt ff)
        && res (frameGoal ff) == g
        && any
          (\sf -> isJust (frameFinal sf) && frameCharacter sf == c && res (frameGoal sf) == g && and [before o x y | x <- IS.toList (frameInterval ff), y <- IS.toList (frameInterval sf)])
          (IM.elems (planFrames plan))
    fulfilled c g s =
      not (isActionStep s)
        && map res (stepPre s) == [g]
        && IM.lookup (stepId s) (planRequired plan) == Just c
        && any
          (\l -> linkTo l == stepId s && any (\f -> frameCharacter f == c && frameFinal f == Just (linkFrom l) && res (frameGoal f) == g) (IM.elems (planFrames plan)))
          (planLinks plan)

    orphanViolations =
      [ lbl (stepId s) <> " is not intentional for " <> symbolText a
      | s <- actionSteps plan
      , not (stepHappening s)
      , a <- stepActors s
      , not (IS.member (stepId s) attempted) || any (\f -> frameAttempt f == Just (stepId s) && frameCharacter f == a) (IM.elems (planFrames plan))
      , not (any (\f -> frameCharacter f == a && IS.member (stepId s) (frameInterval f)) (IM.elems (planFrames plan)))
      ]

-- | Execute one linearisation under the closed-world assumption. An attempted
-- Step changes nothing, and exactly one of its preconditions must be false.
simulate :: Problem -> Plan -> [Text]
simulate prob plan = go (problemInit prob <> planBackstory plan) (linearize plan)
  where
    b = planBindings plan
    go :: Set Atom -> [Step] -> [Text]
    go _ [] = []
    go state (s : rest) =
      let pres = map (resolveLiteral b) (stepPre s)
          failed =
            [ "simulation: " <> prettyLiteral q <> " does not hold before " <> stepLabel plan s
            | q <- pres
            , isGroundLiteral q
            , Set.member (litAtom q) state /= litPositive q
            ]
          attempt = any ((== Just (stepId s)) . frameAttempt) (IM.elems (planFrames plan))
          blocked = ["simulation: attempted step " <> stepLabel plan s <> " has " <> T.pack (show (length failed)) <> " false preconditions, not 1" | length failed /= 1]
          effs = map (resolveLiteral b) (stepEff s)
          state' =
            foldr Set.insert (foldr Set.delete state [litAtom e | e <- effs, not (litPositive e)]) [litAtom e | e <- effs, litPositive e]
       in if attempt then blocked ++ go state rest else failed ++ go (if stepId s == initStepId then state else state') rest
