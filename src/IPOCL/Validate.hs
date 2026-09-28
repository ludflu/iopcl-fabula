-- | An independent check that a plan is complete (Defs. 3 and 6) and that one
-- of its linearisations actually reaches the Outcome from the initial state.
module IPOCL.Validate
  ( validatePlan
  ) where

import Data.IntMap.Strict qualified as IM
import Data.IntSet qualified as IS
import Data.Maybe (isJust)
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
validatePlan :: Mode -> Problem -> Plan -> [Text]
validatePlan mode prob plan =
  concat
    [ supportViolations
    , threatViolations
    , if mode == IPOCL then frameViolations ++ orphanViolations else []
    , simulate prob plan
    ]
  where
    b = planBindings plan
    o = planOrder plan
    steps = planSteps plan
    lbl s = maybe (T.pack (show s)) (stepLabel plan) (IM.lookup s steps)
    res = resolveLiteral b
    initAtoms = problemInit prob
    effectsOf s = maybe [] (map res . stepEff) (IM.lookup s steps)
    provides s l
      | s == initStepId = if litPositive l then Set.member (litAtom l) initAtoms else not (Set.member (litAtom l) initAtoms)
      | otherwise = l `elem` effectsOf s

    supportViolations =
      [ "precondition " <> prettyLiteral (res q) <> " of " <> lbl (stepId s) <> " has no causal link"
      | s <- planStepList plan
      , q <- stepPre s
      , not (any (\l -> linkTo l == stepId s && res (linkCond l) == res q) (planLinks plan))
      ]
        ++ [ "causal link " <> lbl (linkFrom l) <> " -> " <> lbl (linkTo l) <> " is broken"
           | l <- Set.toList (planLinks plan)
           , not (before o (linkFrom l) (linkTo l)) || not (provides (linkFrom l) (res (linkCond l)))
           ]

    threatViolations =
      [ lbl (stepId t) <> " threatens " <> prettyLiteral (res (linkCond l)) <> " from " <> lbl (linkFrom l) <> " to " <> lbl (linkTo l)
      | l <- Set.toList (planLinks plan)
      , t <- planStepList plan
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
              Nothing -> [name <> " has no final step"]
              Just fin ->
                [name <> "'s final step does not achieve its goal" | res (frameGoal f) `notElem` effectsOf fin]
                  ++ [name <> "'s final step is not in its interval" | not (IS.member fin (frameInterval f))]
                  ++ [name <> ": " <> lbl s <> " does not precede the final step" | s <- members, s /= fin, not (before o s fin)]
            ++ case frameMotivator f of
              Nothing -> [name <> " has no motivating step"]
              Just m ->
                [name <> " is not motivated by " <> lbl m | not (provides m (res (frameIntention f)))]
                  ++ [name <> ": motivating step does not precede " <> lbl s | s <- members, not (before o m s)]
    isActor s c = maybe False ((c `elem`) . stepActors) (IM.lookup s steps)

    orphanViolations =
      [ lbl (stepId s) <> " is not intentional for " <> symbolText a
      | s <- actionSteps plan
      , not (stepHappening s)
      , a <- stepActors s
      , not (any (\f -> frameCharacter f == a && IS.member (stepId s) (frameInterval f)) (IM.elems (planFrames plan)))
      ]

-- | Execute one linearisation under the closed-world assumption.
simulate :: Problem -> Plan -> [Text]
simulate prob plan = go (problemInit prob) (linearize plan)
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
          effs = map (resolveLiteral b) (stepEff s)
          state' =
            foldr Set.insert (foldr Set.delete state [litAtom e | e <- effs, not (litPositive e)]) [litAtom e | e <- effs, litPositive e]
       in failed ++ go (if stepId s == initStepId then state else state') rest
