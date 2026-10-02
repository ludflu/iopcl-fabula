-- | Warnings about problems that are well-formed but probably not what the
-- author meant. Unlike 'IPOCL.DomainCheck.checkProblem', none of these stop
-- planning.
module IPOCL.Lint
  ( problemWarnings
  ) where

import Data.Maybe (isNothing)
import Data.Text (Text)
import IPOCL.Bindings
import IPOCL.Ground
import IPOCL.Heuristic
import IPOCL.Pretty
import IPOCL.Syntax

problemWarnings :: Problem -> [Text]
problemWarnings p = concatMap requiredWarnings (problemRequiredFrames p)
  where
    r = reachability (problemInit p) (groundActions p)
    unreachable l = isNothing (literalCost r emptyBindings l)
    requiredWarnings (RequiredFrame c g) =
      let name = "required frame " <> symbolText c <> " wants " <> prettyLiteral g
       in [name <> ": the goal is unreachable" | unreachable g]
            ++ [name <> ": " <> symbolText c <> " can never come to want it" | unreachable (pos (Atom intendsPredicate [TSym c, TLit g]))]
