-- | Warnings about problems that are well-formed but probably not what the
-- author meant. Unlike 'IPOCL.DomainCheck.checkProblem', none of these stop
-- planning.
module IPOCL.Lint
  ( problemWarnings
  ) where

import Data.Maybe (isJust, isNothing)
import Data.Text (Text)
import IPOCL.Bindings
import IPOCL.Ground
import IPOCL.Heuristic
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
       , let blind = reachability (problemInit p) [a | a <- actions, not (any (a `negates`) own)]
       , Just g <- [problemDesire p]
       , isJust (literalCost blind emptyBindings g)
       ]
  where
    actions = groundActions p
    r = reachability (problemInit p) actions
    unreachable l = isNothing (literalCost r emptyBindings l)
    requiredWarnings (RequiredFrame c g) =
      let name = "required frame " <> symbolText c <> " wants " <> prettyLiteral g
       in [name <> ": the goal is unreachable" | unreachable g]
            ++ [name <> ": " <> symbolText c <> " can never come to want it" | unreachable (pos (Atom intendsPredicate [TSym c, TLit g]))]

-- | Some effect of the action can make the belief false.
negates :: GroundAction -> Atom -> Bool
negates a m = any (\e -> not (litPositive e) && isJust (unifyAtoms emptyBindings (litAtom e) m)) (gaEff a)
