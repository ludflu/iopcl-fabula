-- | Warnings about problems that are well-formed but probably not what the
-- author meant. Unlike 'IPOCL.DomainCheck.checkProblem', none of these stop
-- planning.
module IPOCL.Lint
  ( problemWarnings
  , planWarnings
  ) where

import Data.IntMap.Strict qualified as IM
import Data.IntSet qualified as IS
import Data.Maybe (isJust, isNothing)
import Data.Set qualified as Set
import Data.Text (Text)
import IPOCL.Bindings
import IPOCL.Ground
import IPOCL.Heuristic
import IPOCL.Plan
import IPOCL.Pretty
import IPOCL.Syntax

problemWarnings :: Problem -> [Text]
problemWarnings p =
  concatMap requiredWarnings (requiredFrames p)
    ++ [ "misbelief " <> prettyAtom m <> ": no action can overturn it"
       | m <- problemMisbeliefs p
       , not (any (`negates` m) actions)
       ]
    ++ [ "the misbeliefs of " <> symbolText c <> " do not stand in the way of the desire " <> prettyLiteral g
       | Just c <- [problemProtagonist p]
       , let own = [m | m <- problemMisbeliefs p, take 1 (atomArgs m) == [TSym c]]
       , not (null own)
       , let blind = reachabilityWith (backstorySeeds p) (problemInit p) [a | a <- actions, not (any (a `negates`) own)]
       , Just g <- [problemDesire p]
       , isJust (literalCost blind emptyBindings g)
       ]
  where
    actions = groundActions p
    r = problemReachability p
    unreachable l = isNothing (literalCost r emptyBindings l)
    requiredWarnings (RequiredFrame c g) =
      let name = "required frame " <> symbolText c <> " wants " <> prettyLiteral g
       in [name <> ": the goal is unreachable" | unreachable g]
            ++ [name <> ": " <> symbolText c <> " can never come to want it" | unreachable (pos (Atom intendsPredicate [TSym c, TLit g]))]

-- | Some effect of the action can make the belief false.
negates :: GroundAction -> Atom -> Bool
negates a m = any (\e -> not (litPositive e) && isJust (unifyAtoms emptyBindings (litAtom e) m)) (gaEff a)

-- | "An internal change must lead to action": every Realization, and every
-- Step that gives a Character an Intention, needs an outgoing causal or
-- motivation link to a later Step in which that Character is an Actor.
planWarnings :: Problem -> Plan -> [Text]
planWarnings p plan =
  [ stepLabel plan s <> ": the internal change of " <> symbolText c <> " leads to no action by " <> symbolText c
  | s <- actionSteps plan
  , c <- changed s
  , not (any (actsIn c) (successorsOf (stepId s)))
  ]
  where
    b = planBindings plan
    changed s =
      [ c
      | e <- map (resolveLiteral b) (stepEff s)
      , if litPositive e then isIntends e else litAtom e `elem` problemMisbeliefs p
      , TSym c : _ <- [atomArgs (litAtom e)]
      ]
    successorsOf s =
      [linkTo l | l <- Set.toList (planLinks plan), linkFrom l == s]
        ++ [t | f <- IM.elems (planFrames plan), frameMotivator f == Just s, t <- IS.toList (frameInterval f)]
    actsIn c t = maybe False ((c `elem`) . stepActors) (IM.lookup t (planSteps plan))
