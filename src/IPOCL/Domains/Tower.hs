-- | The king, knight and princess of §2.2.1: the princess must end up locked
-- in the tower and the king dead.
module IPOCL.Domains.Tower
  ( towerDomain
  , towerProblem
  , motivatedTowerDomain
  , motivatedTowerProblem
  ) where

import Data.Text (Text)
import IPOCL.Syntax

v :: Text -> Var
v n = Var n 0

towerDomain :: Domain
towerDomain =
  Domain
    { domainName = "tower"
    , domainSchemas = [kill, lockUp]
    , domainPredicateTexts = []
    }

kill :: ActionSchema
kill =
  (schema "kill" ["?killer", "?victim"])
    { schemaActors = [v "killer"]
    , schemaConstraints = [atom "character" ["?killer"], atom "character" ["?victim"]]
    , schemaPrecondition = [PLit (lit "alive" ["?killer"]), PLit (lit "alive" ["?victim"]), neq "?killer" "?victim"]
    , schemaEffect = [nlit "alive" ["?victim"]]
    , schemaText = Just (template "?killer kills ?victim.")
    }

lockUp :: ActionSchema
lockUp =
  (schema "lock-in-tower" ["?jailer", "?prisoner"])
    { schemaActors = [v "jailer"]
    , schemaConstraints = [atom "character" ["?jailer"], atom "character" ["?prisoner"]]
    , schemaPrecondition = [PLit (lit "alive" ["?jailer"]), PLit (lit "alive" ["?prisoner"]), PLit (nlit "locked" ["?prisoner"])]
    , schemaEffect = [lit "locked" ["?prisoner"]]
    , schemaText = Just (template "?jailer locks ?prisoner in the tower.")
    }

towerInit :: [Atom]
towerInit =
  [ atom "character" ["king"]
  , atom "character" ["knight"]
  , atom "character" ["princess"]
  , atom "king" ["king"]
  , atom "knight" ["knight"]
  , atom "princess" ["princess"]
  , atom "alive" ["king"]
  , atom "alive" ["knight"]
  , atom "alive" ["princess"]
  ]

towerOutcome :: [Literal]
towerOutcome = [lit "locked" ["princess"], nlit "alive" ["king"]]

towerProblem :: Problem
towerProblem = problem "tower-1" towerDomain ["king", "knight", "princess"] towerInit towerOutcome

-- | Tower plus Happenings that give the king and the knight their reasons.
motivatedTowerDomain :: Domain
motivatedTowerDomain =
  towerDomain
    { domainName = "motivated-tower"
    , domainSchemas = domainSchemas towerDomain ++ [disobey, witnessCruelty]
    }

disobey :: ActionSchema
disobey =
  (schema "disobey" ["?princess", "?king"])
    { schemaHappening = True
    , schemaConstraints = [atom "princess" ["?princess"], atom "king" ["?king"]]
    , schemaPrecondition = [PLit (lit "alive" ["?princess"]), PLit (lit "alive" ["?king"])]
    , schemaEffect = [lit "angry" ["?king", "?princess"], intends "?king" (Right (lit "locked" ["?princess"]))]
    , schemaText = Just (template "?princess defies ?king.")
    }

witnessCruelty :: ActionSchema
witnessCruelty =
  (schema "witness-cruelty" ["?knight", "?king", "?princess"])
    { schemaHappening = True
    , schemaConstraints = [atom "knight" ["?knight"], atom "king" ["?king"], atom "princess" ["?princess"]]
    , schemaPrecondition = [PLit (lit "locked" ["?princess"]), PLit (lit "alive" ["?knight"])]
    , schemaEffect = [intends "?knight" (Right (nlit "alive" ["?king"]))]
    , schemaText = Just (template "?knight sees that ?king has imprisoned ?princess.")
    }

motivatedTowerProblem :: Problem
motivatedTowerProblem =
  problem "motivated-tower-1" motivatedTowerDomain ["king", "knight", "princess"] towerInit towerOutcome
