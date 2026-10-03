-- | Template narration of a Story (Fig. 13 style).
module IPOCL.Narrate
  ( narrate
  , renderStep
  , renderAttempt
  , renderLiteral
  ) where

import Data.IntMap.Strict qualified as IM
import Data.IntSet qualified as IS
import Data.List (find, nub)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Set qualified as Set
import IPOCL.Bindings
import IPOCL.Ground
import IPOCL.Linearize
import IPOCL.Plan
import IPOCL.Pretty
import IPOCL.Syntax

-- | The Misbeliefs open the Story, followed by one line per Step in
-- linearised order; a Realization gets its own line after its Step. Each Frame's
-- @"<Character> wants <Character goal>."@ line follows its Motivating step,
-- or opens the Story when the initial state motivates it. The first Step of
-- each Interval says what it is for, and the final Step says it got there.
narrate :: Problem -> Plan -> Text
narrate p plan = T.unlines (map believes (problemMisbeliefs p) ++ concatMap stepLines order)
  where
    d = problemDomain p
    order = linearize plan
    stepLines s
      | stepId s == goalStepId = []
      | stepId s == initStepId = wants s
      | not (isActionStep s) = []
      | isUnexecuted plan (stepId s) = renderAttempt d plan s : wants s
      | otherwise = withMotive s (renderStep d plan s) : realizations s ++ wants s
    believes m = renderLiteral d (pos m) <> "."
    realizations s =
      [ symbolText c <> realized belief <> "."
      | e <- stepEff s
      , not (litPositive e)
      , let m = litAtom (resolveLiteral (planBindings plan) e)
      , m `elem` problemMisbeliefs p
      , heldBefore m s
      , TSym c : belief : _ <- [atomArgs m]
      ]
    -- Misbeliefs hold initially; the last executed Step before s that
    -- changes one decides whether it still holds.
    heldBefore m s =
      let earlier = takeWhile ((/= stepId s) . stepId) order
          changes =
            [ litPositive e
            | t <- earlier
            , isActionStep t
            , not (isUnexecuted plan (stepId t))
            , e <- stepEff t
            , litAtom (resolveLiteral (planBindings plan) e) == m
            ]
       in null changes || last changes
    realized = \case
      TLit l -> " realizes " <> renderLiteral d (negateLit l)
      t -> " no longer believes " <> renderTerm d t
    -- A failed Frame and its successful retry share one Intention.
    wants s =
      nub
        [ symbolText (frameCharacter f) <> " wants " <> goal (resolvedGoal plan f) <> "."
        | f <- IM.elems (planFrames plan)
        , frameMotivator f == Just (stepId s)
        ]
    goal l
      | litPositive l = renderLiteral d l
      | otherwise = "it not to be the case that " <> renderLiteral d (negateLit l)
    position = IM.fromList (zip (map stepId order) [0 :: Int ..])
    firstOf f = fst <$> IS.minView (IS.map (\s -> IM.findWithDefault maxBound s position) (frameInterval f))
    opens s = [f | f <- IM.elems (planFrames plan), (== Just (position IM.! stepId s)) (firstOf f)]
    closes s = [f | f <- IM.elems (planFrames plan), frameFinal f == Just (stepId s)]
    goals fs = T.intercalate " and " (map (renderLiteral d . resolvedGoal plan) fs)
    withMotive s text =
      let opening = opens s
          closing = filter (`notElem` opening) (closes s)
          sentence = stripPeriod text
       in case (opening, closing) of
            ([], []) -> text
            (_, []) -> sentence <> " so that " <> goals opening <> "."
            ([], _) -> sentence <> ", and so " <> goals closing <> "."
            (_, _) -> sentence <> " so that " <> goals opening <> ", and so " <> goals closing <> "."
    stripPeriod t = fromMaybe t (T.stripSuffix "." t)

-- | A Step through its schema's @:text@ template, or @"name arg1 arg2"@.
renderStep :: Domain -> Plan -> Step -> Text
renderStep d plan s = case stepAction s of
  Nothing -> stepLabel plan s
  Just g ->
    let sch = gaSchema g
        args = map (renderTerm d . resolve (planBindings plan)) (stepArgs s)
     in case schemaText sch of
          Just t -> fillTemplate (zip (map varName (schemaParams sch)) args) t
          Nothing -> T.unwords (schemaName sch : args)

-- | A blocked attempt: @"<attempt text>, but <blocker>."@. The attempt text
-- comes from the schema's @:attempt-text@, or is @"<Character> tries to name args"@.
renderAttempt :: Domain -> Plan -> Step -> Text
renderAttempt d plan s = tries <> but <> "."
  where
    b = planBindings plan
    args = map (renderTerm d . resolve b) (stepArgs s)
    who = maybe "?" (symbolText . frameCharacter) (find ((== Just (stepId s)) . frameAttempt) (IM.elems (planFrames plan)))
    tries = case gaSchema <$> stepAction s of
      Just sch
        | Just t <- schemaAttemptText sch -> fillTemplate (zip (map varName (schemaParams sch)) args) t
        | otherwise -> who <> " tries to " <> T.unwords (schemaName sch : args)
      Nothing -> who <> " tries"
    pres = map (resolveLiteral b) (stepPre s)
    blockers =
      [ renderLiteral d (resolveLiteral b (linkCond l))
      | l <- Set.toList (planLinks plan)
      , linkTo l == stepId s
      , resolveLiteral b (negateLit (linkCond l)) `elem` pres
      ]
    but = if null blockers then "" else ", but " <> T.intercalate " and " blockers

-- | A literal through the domain's predicate templates, falling back to its
-- printed form.
renderLiteral :: Domain -> Literal -> Text
renderLiteral d l@(Literal positive (Atom p args)) =
  case find ((== p) . ptPredicate) (domainPredicateTexts d) of
    Just pt
      | length (ptParams pt) == length args ->
          negation (fillTemplate (zip (map varName (ptParams pt)) (map (renderTerm d) args)) (ptTemplate pt))
    _ -> prettyLiteral l
  where
    negation t = if positive then t else "it is not the case that " <> t

renderTerm :: Domain -> Term -> Text
renderTerm d = \case
  TLit l -> renderLiteral d l
  t -> prettyTerm t

fillTemplate :: [(Text, Text)] -> Template -> Text
fillTemplate env = T.concat . map part
  where
    part = \case
      TText t -> t
      TParam n -> fromMaybe ("?" <> n) (lookup n env)
