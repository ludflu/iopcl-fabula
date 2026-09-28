-- | The smallest useful problem: one Action schema achieves the Outcome.
module IPOCL.Domains.Tiny (tinyDomain, tinyProblem) where

import IPOCL.Syntax

tinyDomain :: Domain
tinyDomain =
  Domain
    { domainName = "tiny"
    , domainSchemas =
        [ (schema "wake-up" ["?who"])
            { schemaActors = [Var "who" 0]
            , schemaConstraints = [atom "character" ["?who"]]
            , schemaPrecondition = [PLit (lit "asleep" ["?who"])]
            , schemaEffect = [nlit "asleep" ["?who"], lit "awake" ["?who"]]
            , schemaText = Just (template "?who wakes up.")
            }
        ]
    , domainPredicateTexts = []
    }

tinyProblem :: Problem
tinyProblem =
  problem
    "tiny-1"
    tinyDomain
    ["hero"]
    [ atom "character" ["hero"]
    , atom "asleep" ["hero"]
    , litAtom (intends "hero" (Right (lit "awake" ["hero"])))
    ]
    [lit "awake" ["hero"]]
