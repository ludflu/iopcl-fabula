-- | Template narration of a Story (Fig. 13 style).
module IPOCL.Narrate
  ( narrate
  , renderStep
  , renderLiteral
  ) where

import Data.IntMap.Strict qualified as IM
import Data.List (find)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import IPOCL.Bindings
import IPOCL.Ground
import IPOCL.Linearize
import IPOCL.Plan
import IPOCL.Pretty
import IPOCL.Syntax

-- | One line per Step in linearised order. Each Frame's
-- @"<Character> wants <Character goal>."@ line follows its Motivating step,
-- or opens the Story when the initial state motivates it.
narrate :: Problem -> Plan -> Text
narrate p plan = T.unlines (concatMap stepLines (linearize plan))
  where
    d = problemDomain p
    stepLines s
      | stepId s == goalStepId = []
      | stepId s == initStepId = wants s
      | otherwise = renderStep d plan s : wants s
    wants s =
      [ symbolText (frameCharacter f) <> " wants " <> goal (resolvedGoal plan f) <> "."
      | f <- IM.elems (planFrames plan)
      , frameMotivator f == Just (stepId s)
      ]
    goal l
      | litPositive l = renderLiteral d l
      | otherwise = "it not to be the case that " <> renderLiteral d (negateLit l)

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
