-- | A king orders his knight to bring him the lamp: the knight's goal is a
-- literal passed through the order's @?objective@ parameter.
module FetchDomain (fetchProblem) where

import IPOCL.Syntax

fetchProblem :: Problem
fetchProblem =
  problem
    "fetch-1"
    fetchDomain
    ["king", "knight"]
    [ atom "king" ["king"]
    , atom "knight" ["knight"]
    , atom "character" ["king"]
    , atom "character" ["knight"]
    , atom "thing" ["lamp"]
    , atom "loyal-to" ["knight", "king"]
    , atom "has" ["knight", "lamp"]
    , litAtom (intends "king" (Right (intends "knight" (Right (lit "has" ["king", "lamp"])))))
    ]
    [lit "has" ["king", "lamp"]]

fetchDomain :: Domain
fetchDomain =
  Domain
    { domainName = "fetch"
    , domainSchemas =
        [ (schema "order" ["?king", "?knight", "?objective"])
            { schemaActors = [Var "king" 0]
            , schemaConstraints = [atom "king" ["?king"], atom "knight" ["?knight"]]
            , schemaPrecondition = [PLit (lit "loyal-to" ["?knight", "?king"])]
            , schemaEffect = [intends "?knight" (Left "?objective")]
            }
        , (schema "give" ["?giver", "?givee", "?thing"])
            { schemaActors = [Var "giver" 0]
            , schemaConstraints = [atom "character" ["?giver"], atom "character" ["?givee"], atom "thing" ["?thing"]]
            , schemaPrecondition = [PLit (lit "has" ["?giver", "?thing"]), neq "?giver" "?givee"]
            , schemaEffect = [nlit "has" ["?giver", "?thing"], lit "has" ["?givee", "?thing"]]
            }
        ]
    , domainPredicateTexts = []
    }
