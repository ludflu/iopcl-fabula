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
    ++ checkInnerStory
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
      ThirdRail -> needsProtagonist "third-rail"
      ServesProtagonist c -> unknown c ++ needsProtagonist "serves-protagonist"
    needsProtagonist n = ["preference " <> n <> " needs a protagonist" | Nothing <- [problemProtagonist p]]
    checkRequired (RequiredFrame c g) =
      ["required frame names unknown character " <> symbolText c | not (Set.member c (problemCharacters p))]
        ++ ["required frame goal " <> prettyLiteral g <> " must be ground" | not (isGroundLiteral g)]
        ++ ["required frame goal may not be an intention" | isIntends g]
    checkInnerStory =
      [ "protagonist " <> symbolText c <> " is not a character"
      | Just c <- [problemProtagonist p]
      , not (Set.member c (problemCharacters p))
      ]
        ++ ["a desire needs a protagonist" | Nothing <- [problemProtagonist p], Just _ <- [problemDesire p]]
        ++ [ "the protagonist " <> symbolText c <> " does not intend the desire " <> prettyLiteral g <> " in the initial state"
           | Just c <- [problemProtagonist p]
           , Just g <- [problemDesire p]
           , not (Set.member (Atom intendsPredicate [TSym c, TLit g]) (problemInit p))
           ]
        ++ concatMap checkMisbelief (problemMisbeliefs p)
    checkMisbelief m =
      let name = "misbelief " <> prettyAtom m
       in [name <> " is not a believes fact" | atomPredicate m /= believesPredicate]
            ++ [name <> " does not hold in the initial state" | not (Set.member m (problemInit p))]
            ++ case atomArgs m of
              TSym c : _ : _ | Set.member c (problemCharacters p) -> []
              _ -> [name <> ": its first argument must be a character, followed by the belief"]
    unknown c = ["preference names unknown character " <> symbolText c | not (Set.member c (problemCharacters p))]
