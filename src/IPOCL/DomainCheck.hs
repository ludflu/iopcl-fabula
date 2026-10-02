-- | Static checks on problems before planning (spec §4.1).
module IPOCL.DomainCheck
  ( checkProblem
  ) where

import Data.List (nub)
import Data.Set qualified as Set
import Data.Text (Text)
import IPOCL.Ground (staticPredicates)
import IPOCL.Pretty
import IPOCL.Syntax

-- | Every problem found; an empty list means the problem is usable.
checkProblem :: Problem -> [Text]
checkProblem p = concatMap checkSchema (domainSchemas d) ++ concatMap checkPreference (problemPreferences p)
    ++ concatMap checkRequired (problemRequiredFrames p)
  where
    d = problemDomain p
    statics = staticPredicates d
    checkSchema s =
      let n = "action " <> schemaName s <> ": "
          params = schemaParams s
          constrained = concatMap atomVars (schemaConstraints s)
          pres = [l | PLit l <- schemaPrecondition s]
          preVars = concatMap literalVars pres ++ concat [termVars a ++ termVars b | PNeq a b <- schemaPrecondition s]
       in [n <> "intends may not appear in a precondition" | any isIntends pres]
            ++ [n <> "intends may not appear in a constraint" | any ((== intendsPredicate) . atomPredicate) (schemaConstraints s)]
            ++ [n <> "an effect may not negate an intention" | any (\e -> isIntends e && not (litPositive e)) (schemaEffect s)]
            ++ [ n <> "effect " <> prettyLiteral e <> " changes the static predicate " <> atomPredicate (litAtom e)
               | e <- schemaEffect s
               , atomPredicate (litAtom e) `Set.member` statics
               ]
            ++ [n <> "actor ?" <> varName v <> " is not a parameter" | v <- schemaActors s, v `notElem` params]
            ++ [ n <> "actor ?" <> varName v <> " must be bound by a constraint"
               | v <- schemaActors s
               , v `elem` params
               , v `notElem` constrained
               ]
            ++ [ n <> "variable ?" <> varName v <> " is not a parameter"
               | v <- nub (preVars ++ concatMap literalVars (schemaEffect s) ++ constrained)
               , v `notElem` params
               ]
            ++ [n <> "a non-happening action needs at least one actor" | not (schemaHappening s), null (schemaActors s)]
    checkPreference pr = case prefRule pr of
      AllowGoals c _ -> unknown c
      ForbidGoal c _ -> unknown c
      MaxFrames c _ -> unknown c
      NoRepeatSteps -> []
    checkRequired (RequiredFrame c g) =
      ["required frame names unknown character " <> symbolText c | not (Set.member c (problemCharacters p))]
        ++ ["required frame goal " <> prettyLiteral g <> " must be ground" | not (isGroundLiteral g)]
        ++ ["required frame goal may not be an intention" | isIntends g]
    unknown c = ["preference names unknown character " <> symbolText c | not (Set.member c (problemCharacters p))]
