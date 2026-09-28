-- | The Aladdin evaluation domain of Appendix A.1.
module IPOCL.Domains.Aladdin (aladdinDomain, aladdinProblem, aladdinInit) where

import Data.Text (Text)
import IPOCL.Syntax

v :: Text -> Var
v n = Var n 0

p :: Text -> [Text] -> Precond
p n = PLit . lit n

np :: Text -> [Text] -> Precond
np n = PLit . nlit n

aladdinDomain :: Domain
aladdinDomain =
  Domain
    { domainName = "aladdin"
    , domainSchemas =
        [ travel
        , slay
        , pillage
        , give
        , summon
        , loveSpell
        , marry
        , fallInLove
        , order
        , command
        , appearThreatening
        ]
    , domainPredicateTexts =
        [ PredicateText "alive" [v "x"] (template "?x is alive")
        , PredicateText "loves" [v "a", v "b"] (template "?a loves ?b")
        , PredicateText "has" [v "a", v "b"] (template "?a has ?b")
        , PredicateText "married-to" [v "a", v "b"] (template "?a is married to ?b")
        , PredicateText "at" [v "a", v "b"] (template "?a is at ?b")
        ]
    }

travel, slay, pillage, give, summon, loveSpell, marry, fallInLove, order, command, appearThreatening :: ActionSchema
travel =
  (schema "travel" ["?traveller", "?from", "?dest"])
    { schemaActors = [v "traveller"]
    , schemaConstraints = [atom "character" ["?traveller"], atom "place" ["?from"], atom "place" ["?dest"]]
    , schemaPrecondition = [p "at" ["?traveller", "?from"], p "alive" ["?traveller"], neq "?from" "?dest"]
    , schemaEffect = [nlit "at" ["?traveller", "?from"], lit "at" ["?traveller", "?dest"]]
    , schemaText = Just (template "?traveller travels from ?from to ?dest.")
    }
slay =
  (schema "slay" ["?slayer", "?monster", "?place"])
    { schemaActors = [v "slayer"]
    , schemaConstraints = [atom "knight" ["?slayer"], atom "monster" ["?monster"], atom "place" ["?place"]]
    , schemaPrecondition = [p "at" ["?slayer", "?place"], p "at" ["?monster", "?place"], p "alive" ["?slayer"], p "alive" ["?monster"]]
    , schemaEffect = [nlit "alive" ["?monster"]]
    , schemaText = Just (template "?slayer slays ?monster.")
    }
pillage =
  (schema "pillage" ["?pillager", "?body", "?thing", "?place"])
    { schemaActors = [v "pillager"]
    , schemaConstraints = [atom "character" ["?pillager"], atom "character" ["?body"], atom "thing" ["?thing"], atom "place" ["?place"]]
    , schemaPrecondition =
        [ p "at" ["?pillager", "?place"]
        , p "at" ["?body", "?place"]
        , p "has" ["?body", "?thing"]
        , np "alive" ["?body"]
        , p "alive" ["?pillager"]
        , neq "?pillager" "?body"
        ]
    , schemaEffect = [nlit "has" ["?body", "?thing"], lit "has" ["?pillager", "?thing"]]
    , schemaText = Just (template "?pillager takes ?thing from the dead body of ?body.")
    }
give =
  (schema "give" ["?giver", "?givee", "?thing", "?place"])
    { schemaActors = [v "giver"]
    , schemaConstraints = [atom "character" ["?giver"], atom "character" ["?givee"], atom "thing" ["?thing"], atom "place" ["?place"]]
    , schemaPrecondition =
        [ p "at" ["?giver", "?place"]
        , p "at" ["?givee", "?place"]
        , p "has" ["?giver", "?thing"]
        , p "alive" ["?giver"]
        , p "alive" ["?givee"]
        , neq "?giver" "?givee"
        ]
    , schemaEffect = [nlit "has" ["?giver", "?thing"], lit "has" ["?givee", "?thing"]]
    , schemaText = Just (template "?giver hands ?thing to ?givee.")
    }
summon =
  (schema "summon" ["?char", "?genie", "?lamp", "?place"])
    { schemaActors = [v "char"]
    , schemaConstraints = [atom "character" ["?char"], atom "genie" ["?genie"], atom "magic-lamp" ["?lamp"], atom "place" ["?place"]]
    , schemaPrecondition =
        [ p "at" ["?char", "?place"]
        , p "has" ["?char", "?lamp"]
        , p "in" ["?genie", "?lamp"]
        , p "alive" ["?char"]
        , p "alive" ["?genie"]
        , neq "?char" "?genie"
        ]
    , schemaEffect =
        [ lit "at" ["?genie", "?place"]
        , nlit "in" ["?genie", "?lamp"]
        , nlit "confined" ["?genie"]
        , lit "controls" ["?char", "?genie", "?lamp"]
        ]
    , schemaText = Just (template "?char rubs ?lamp and summons ?genie out of it.")
    }
loveSpell =
  (schema "love-spell" ["?genie", "?target", "?lover"])
    { schemaActors = [v "genie"]
    , schemaConstraints = [atom "genie" ["?genie"], atom "character" ["?target"], atom "character" ["?lover"]]
    , schemaPrecondition =
        [ np "confined" ["?genie"]
        , np "loves" ["?target", "?lover"]
        , p "alive" ["?genie"]
        , p "alive" ["?target"]
        , p "alive" ["?lover"]
        , neq "?genie" "?target"
        , neq "?genie" "?lover"
        , neq "?target" "?lover"
        ]
    , schemaEffect = [lit "loves" ["?target", "?lover"], intends "?target" (Right (lit "married-to" ["?target", "?lover"]))]
    , schemaText = Just (template "?genie casts a spell on ?target making them fall in love with ?lover.")
    }
marry =
  (schema "marry" ["?groom", "?bride", "?place"])
    { schemaActors = [v "groom", v "bride"]
    , schemaConstraints = [atom "male" ["?groom"], atom "female" ["?bride"], atom "place" ["?place"]]
    , schemaPrecondition =
        [ p "at" ["?groom", "?place"]
        , p "at" ["?bride", "?place"]
        , p "loves" ["?groom", "?bride"]
        , p "loves" ["?bride", "?groom"]
        , p "alive" ["?groom"]
        , p "alive" ["?bride"]
        ]
    , schemaEffect =
        [ lit "married" ["?groom"]
        , lit "married" ["?bride"]
        , nlit "single" ["?groom"]
        , nlit "single" ["?bride"]
        , lit "married-to" ["?groom", "?bride"]
        , lit "married-to" ["?bride", "?groom"]
        ]
    , schemaText = Just (template "?groom and ?bride wed in an extravagant ceremony.")
    }
fallInLove =
  (schema "fall-in-love" ["?male", "?female", "?place"])
    { schemaActors = [v "male"]
    , schemaHappening = True
    , schemaConstraints = [atom "male" ["?male"], atom "female" ["?female"], atom "place" ["?place"]]
    , schemaPrecondition =
        [ p "at" ["?male", "?place"]
        , p "at" ["?female", "?place"]
        , p "single" ["?male"]
        , p "alive" ["?male"]
        , p "alive" ["?female"]
        , np "loves" ["?male", "?female"]
        , np "loves" ["?female", "?male"]
        , p "beautiful" ["?female"]
        ]
    , schemaEffect = [lit "loves" ["?male", "?female"], intends "?male" (Right (lit "married-to" ["?male", "?female"]))]
    , schemaText = Just (template "?male sees ?female and instantly falls in love.")
    }
order =
  (schema "order" ["?king", "?knight", "?place", "?objective"])
    { schemaActors = [v "king"]
    , schemaConstraints = [atom "king" ["?king"], atom "knight" ["?knight"], atom "place" ["?place"]]
    , schemaPrecondition =
        [ p "at" ["?king", "?place"]
        , p "at" ["?knight", "?place"]
        , p "alive" ["?king"]
        , p "alive" ["?knight"]
        , p "loyal-to" ["?knight", "?king"]
        ]
    , schemaEffect = [intends "?knight" (Left "?objective")]
    , schemaText = Just (template "?king orders ?knight.")
    }
command =
  (schema "command" ["?char", "?genie", "?lamp", "?objective"])
    { schemaActors = [v "char"]
    , schemaConstraints = [atom "character" ["?char"], atom "genie" ["?genie"], atom "magic-lamp" ["?lamp"]]
    , schemaPrecondition =
        [ p "has" ["?char", "?lamp"]
        , p "controls" ["?char", "?genie", "?lamp"]
        , p "alive" ["?char"]
        , p "alive" ["?genie"]
        , neq "?char" "?genie"
        ]
    , schemaEffect = [intends "?genie" (Left "?objective")]
    , schemaText = Just (template "?char uses ?lamp to command ?genie.")
    }
appearThreatening =
  (schema "appear-threatening" ["?monster", "?char", "?place"])
    { schemaActors = [v "monster"]
    , schemaHappening = True
    , schemaConstraints = [atom "monster" ["?monster"], atom "character" ["?char"], atom "place" ["?place"]]
    , schemaPrecondition = [p "at" ["?monster", "?place"], p "at" ["?char", "?place"], p "scary" ["?monster"], neq "?monster" "?char"]
    , schemaEffect = [intends "?char" (Right (nlit "alive" ["?monster"]))]
    , schemaText = Just (template "?monster appears threatening to ?char.")
    }

aladdinInit :: [Atom]
aladdinInit =
  [ atom "character" ["aladdin"]
  , atom "male" ["aladdin"]
  , atom "knight" ["aladdin"]
  , atom "at" ["aladdin", "castle"]
  , atom "alive" ["aladdin"]
  , atom "single" ["aladdin"]
  , atom "loyal-to" ["aladdin", "jafar"]
  , atom "character" ["jafar"]
  , atom "male" ["jafar"]
  , atom "king" ["jafar"]
  , atom "at" ["jafar", "castle"]
  , atom "alive" ["jafar"]
  , atom "single" ["jafar"]
  , atom "character" ["jasmine"]
  , atom "female" ["jasmine"]
  , atom "at" ["jasmine", "castle"]
  , atom "alive" ["jasmine"]
  , atom "single" ["jasmine"]
  , atom "beautiful" ["jasmine"]
  , atom "character" ["dragon"]
  , atom "monster" ["dragon"]
  , atom "dragon" ["dragon"]
  , atom "at" ["dragon", "mountain"]
  , atom "alive" ["dragon"]
  , atom "scary" ["dragon"]
  , atom "character" ["genie"]
  , atom "monster" ["genie"]
  , atom "genie" ["genie"]
  , atom "in" ["genie", "lamp"]
  , atom "confined" ["genie"]
  , atom "alive" ["genie"]
  , atom "scary" ["genie"]
  , atom "place" ["castle"]
  , atom "place" ["mountain"]
  , atom "thing" ["lamp"]
  , atom "magic-lamp" ["lamp"]
  , atom "has" ["dragon", "lamp"]
  ]

aladdinProblem :: Problem
aladdinProblem =
  problem
    "aladdin-1"
    aladdinDomain
    ["aladdin", "jafar", "jasmine", "dragon", "genie"]
    aladdinInit
    [lit "married-to" ["jafar", "jasmine"], nlit "alive" ["genie"]]
