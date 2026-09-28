-- | The arch-villain who bribes the President (§4.4, Fig. 9).
module IPOCL.Domains.Bribe (bribeDomain, bribeProblem) where

import Data.Text (Text)
import IPOCL.Syntax

v :: Text -> Var
v n = Var n 0

bribeDomain :: Domain
bribeDomain =
  Domain
    { domainName = "bribe"
    , domainSchemas = [bribe, give, coerce]
    , domainPredicateTexts =
        [ PredicateText "has" [v "a", v "b"] (template "?a has ?b")
        , PredicateText "controls" [v "a", v "b"] (template "?a controls ?b")
        , PredicateText "corrupt" [v "a"] (template "?a is corrupt")
        ]
    }

bribe :: ActionSchema
bribe =
  (schema "bribe" ["?briber", "?official", "?thing"])
    { schemaActors = [v "briber"]
    , schemaConstraints = [atom "character" ["?briber"], atom "official" ["?official"], atom "thing" ["?thing"]]
    , schemaPrecondition = [PLit (lit "has" ["?briber", "?thing"]), neq "?briber" "?official"]
    , schemaEffect =
        [ lit "corrupt" ["?official"]
        , lit "controls" ["?briber", "?official"]
        , lit "has" ["?official", "?thing"]
        , nlit "has" ["?briber", "?thing"]
        ]
    , schemaText = Just (template "?briber bribes ?official with ?thing.")
    }

give :: ActionSchema
give =
  (schema "give" ["?giver", "?givee", "?thing"])
    { schemaActors = [v "giver"]
    , schemaConstraints = [atom "character" ["?giver"], atom "character" ["?givee"], atom "thing" ["?thing"]]
    , schemaPrecondition = [PLit (lit "has" ["?giver", "?thing"]), neq "?giver" "?givee"]
    , schemaEffect = [nlit "has" ["?giver", "?thing"], lit "has" ["?givee", "?thing"]]
    , schemaText = Just (template "?giver gives ?thing to ?givee.")
    }

coerce :: ActionSchema
coerce =
  (schema "coerce" ["?coercer", "?victim", "?objective"])
    { schemaActors = [v "coercer"]
    , schemaConstraints = [atom "can-threaten" ["?coercer", "?victim"]]
    , schemaEffect = [intends "?victim" (Left "?objective")]
    , schemaText = Just (template "?coercer coerces ?victim.")
    }

bribeProblem :: Problem
bribeProblem =
  problem
    "bribe-1"
    bribeDomain
    ["villain", "hero", "president"]
    [ atom "character" ["villain"]
    , atom "character" ["hero"]
    , atom "character" ["president"]
    , atom "official" ["president"]
    , atom "thing" ["money"]
    , atom "can-threaten" ["villain", "hero"]
    , atom "has" ["hero", "money"]
    , litAtom (intends "villain" (Right (lit "controls" ["villain", "president"])))
    ]
    [lit "corrupt" ["president"]]
