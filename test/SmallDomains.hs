-- | Small problems that isolate one planner behaviour each.
module SmallDomains (marriageProblem, sleepyProblem, giftProblem) where

import IPOCL.Domains.Aladdin
import IPOCL.Syntax

-- | Reduced Aladdin: the genie is already free and already wants Jasmine to
-- love Jafar, so the story is love-spell, fall-in-love and the wedding.
marriageProblem :: Problem
marriageProblem =
  problem
    "marriage"
    aladdinDomain
    ["jafar", "jasmine", "genie"]
    [ atom "character" ["jafar"]
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
    , atom "character" ["genie"]
    , atom "genie" ["genie"]
    , atom "at" ["genie", "castle"]
    , atom "alive" ["genie"]
    , atom "place" ["castle"]
    , litAtom (intends "genie" (Right (lit "loves" ["jasmine", "jafar"])))
    ]
    [lit "married-to" ["jafar", "jasmine"]]

-- | The hero must first want to be awake (to read) and later want not to be
-- awake (to end the story asleep): two Frames with complementary goals.
sleepyProblem :: Problem
sleepyProblem =
  problem
    "sleepy"
    sleepyDomain
    ["hero"]
    [ atom "character" ["hero"]
    , atom "asleep" ["hero"]
    , litAtom (intends "hero" (Right (lit "awake" ["hero"])))
    , litAtom (intends "hero" (Right (nlit "awake" ["hero"])))
    ]
    [lit "has-read" ["hero"], lit "asleep" ["hero"]]

sleepyDomain :: Domain
sleepyDomain =
  Domain
    { domainName = "sleepy"
    , domainSchemas =
        [ (schema "wake-up" ["?who"])
            { schemaActors = [Var "who" 0]
            , schemaConstraints = [atom "character" ["?who"]]
            , schemaPrecondition = [PLit (lit "asleep" ["?who"])]
            , schemaEffect = [nlit "asleep" ["?who"], lit "awake" ["?who"]]
            }
        , (schema "fall-asleep" ["?who"])
            { schemaActors = [Var "who" 0]
            , schemaConstraints = [atom "character" ["?who"]]
            , schemaPrecondition = [PLit (lit "tired" ["?who"])]
            , schemaEffect = [lit "asleep" ["?who"], nlit "awake" ["?who"]]
            }
        , (schema "read" ["?who"])
            { schemaHappening = True
            , schemaConstraints = [atom "character" ["?who"]]
            , schemaPrecondition = [PLit (lit "awake" ["?who"])]
            , schemaEffect = [lit "has-read" ["?who"], lit "tired" ["?who"]]
            }
        ]
    , domainPredicateTexts = []
    }

-- | The bard can please the king by singing or with a gift, and intends both
-- that the king is happy and that the king is rich.
giftProblem :: Problem
giftProblem =
  problem
    "gift"
    Domain
      { domainName = "gift"
      , domainSchemas =
          [ (schema "sing" ["?who"])
              { schemaActors = [Var "who" 0]
              , schemaConstraints = [atom "character" ["?who"]]
              , schemaEffect = [lit "happy" ["king"]]
              }
          , (schema "give-gold" ["?who"])
              { schemaActors = [Var "who" 0]
              , schemaConstraints = [atom "character" ["?who"]]
              , schemaEffect = [lit "happy" ["king"], lit "rich" ["king"]]
              }
          ]
      , domainPredicateTexts = []
      }
    ["bard"]
    [ atom "character" ["bard"]
    , litAtom (intends "bard" (Right (lit "happy" ["king"])))
    , litAtom (intends "bard" (Right (lit "rich" ["king"])))
    ]
    [lit "happy" ["king"]]
