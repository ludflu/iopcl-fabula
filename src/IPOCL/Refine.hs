-- | Plan refinement: flaw detection and the refinement operators of Fig. 5.
module IPOCL.Refine
  ( Env (..)
  , mkEnv
  , Child (..)
  , Expansion (..)
  , flaws
  , expand
  , refine
  ) where

import Control.Monad (foldM)
import Data.IntMap.Strict qualified as IM
import Data.List (sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import IPOCL.Bindings
import IPOCL.Ground
import IPOCL.Order
import IPOCL.Plan
import IPOCL.Pretty
import IPOCL.Syntax

data Env = Env
  { envProblem :: !Problem
  , envMode :: !Mode
  , envActions :: ![GroundAction]
  , envEffectIndex :: !(Map (Bool, Text) [(GroundAction, Literal)])
  , envInit :: !(Set Atom)
  , envPrune :: Plan -> Bool
  -- ^ Hard pruning (e.g. hard Author preferences); 'True' drops the plan.
  }

mkEnv :: Mode -> Problem -> Env
mkEnv mode p = mkEnvWith mode p (groundActions p)

mkEnvWith :: Mode -> Problem -> [GroundAction] -> Env
mkEnvWith mode p gas =
  Env
    { envProblem = p
    , envMode = mode
    , envActions = gas
    , envEffectIndex = Map.fromListWith (flip (++)) [((litPositive e, atomPredicate (litAtom e)), [(g, e)]) | g <- gas, e <- gaEff g]
    , envInit = problemInit p
    , envPrune = const False
    }

data Child = Child {childPlan :: !Plan, childReason :: !Text}

data Expansion
  = Solution
  | DeadEnd
  | Refined !Flaw ![Child]

-- | All flaws of a plan: threats first, then the rest in tie-break order.
flaws :: Env -> Plan -> [Flaw]
flaws _ plan = causalThreats plan ++ [OpenCondition s l | (s, l) <- planOpenConds plan]

isThreat :: Flaw -> Bool
isThreat = \case
  CausalThreat {} -> True
  IntentionalThreat {} -> True
  _ -> False

-- | Select a flaw and produce its children, or recognise a solution / dead end.
-- Threats are repaired first; otherwise the flaw with the fewest children.
expand :: Env -> Plan -> Expansion
expand env plan = case flaws env plan of
  [] -> Solution
  f : _ | isThreat f -> result f (refine env plan f)
  fs ->
    let scored = [(length kids, i, fl, kids) | (i, fl) <- zip [0 :: Int ..] fs, let kids = refine env plan fl]
     in case sortOn (\(k, i, _, _) -> (k, i)) scored of
          (_, _, f, cs) : _ -> result f cs
          [] -> Solution
  where
    result _ [] = DeadEnd
    result f cs = Refined f cs

refine :: Env -> Plan -> Flaw -> [Child]
refine env plan = \case
  OpenCondition s p -> openCondition env plan s p
  CausalThreat t l -> resolveCausalThreat env plan t l
  _ -> []

-- Causal threats ------------------------------------------------------------

-- | Steps that may fall inside a causal link and assert the negation of its condition.
causalThreats :: Plan -> [Flaw]
causalThreats plan =
  [ CausalThreat (stepId t) l
  | l <- Set.toList (planLinks plan)
  , t <- planStepList plan
  , stepId t /= linkFrom l
  , stepId t /= linkTo l
  , possiblyBefore o (linkFrom l) (stepId t)
  , possiblyBefore o (stepId t) (linkTo l)
  , any (\e -> unifyLiterals b e (negateLit (linkCond l)) /= Nothing) (stepEff t)
  ]
  where
    o = planOrder plan
    b = planBindings plan

resolveCausalThreat :: Env -> Plan -> StepId -> CausalLink -> [Child]
resolveCausalThreat env plan t l =
  [Child p' ("promote step " <> tshow t) | Just p' <- [ordered (linkTo l) t]]
    ++ [Child p' ("demote step " <> tshow t) | Just p' <- [ordered t (linkFrom l)]]
    ++ [Child p' ("separate step " <> tshow t) | p' <- separations]
  where
    b = planBindings plan
    ordered a c = do
      o <- addOrder a c (planOrder plan)
      keep env plan {planOrder = o, planThreatOrders = Set.insert (a, c) (planThreatOrders plan)}
    cond = resolveLiteral b (negateLit (linkCond l))
    -- For each clobbering effect that only possibly codesignates, forbid one
    -- of the argument equalities it relies on.
    separations =
      [ plan {planBindings = b'}
      | Just step <- [IM.lookup t (planSteps plan)]
      , e <- map (resolveLiteral b) (stepEff step)
      , litPositive e == litPositive cond
      , unifyLiterals b e cond /= Nothing
      , e /= cond
      , (x, y) <- zip (atomArgs (litAtom e)) (atomArgs (litAtom cond))
      , x /= y
      , Just b' <- [addNeq b x y]
      , not (envPrune env plan {planBindings = b'})
      ]

-- Causal planning ---------------------------------------------------------

openCondition :: Env -> Plan -> StepId -> Literal -> [Child]
openCondition env plan0 sNeed p =
  [ Child plan' (establishReason plan' est p)
  | est <- establishers env plan sNeed p
  , Just plan' <- [finish est]
  ]
  where
    plan = plan0 {planOpenConds = filter (/= (sNeed, p)) (planOpenConds plan0)}
    finish (Establisher pl sAdd _) = do
      o <- addOrder sAdd sNeed (planOrder pl)
      keep env pl {planOrder = o, planLinks = Set.insert (CausalLink sAdd p sNeed) (planLinks pl)}

keep :: Env -> Plan -> Maybe Plan
keep env pl = if envPrune env pl then Nothing else Just pl

establishReason :: Plan -> Establisher -> Literal -> Text
establishReason pl (Establisher _ s isNew) p =
  (if isNew then "created new step " else "reused step ")
    <> tshow s
    <> ": "
    <> maybe "?" (stepLabel pl) (IM.lookup s (planSteps pl))
    <> " to solve "
    <> prettyLiteral (resolveLiteral (planBindings pl) p)

data Establisher = Establisher
  { estPlan :: !Plan
  , estStep :: !StepId
  , estNew :: !Bool
  }

-- | Ways to make @p@ true, via existing Steps (including the initial state
-- under the closed-world assumption) or a new Step. The consumer is never used
-- as its own establisher.
establishers :: Env -> Plan -> StepId -> Literal -> [Establisher]
establishers env plan consumer p = existing ++ closedWorld ++ new
  where
    b = planBindings plan
    existing =
      [ Establisher plan {planBindings = b'} (stepId s) False
      | s <- planStepList plan
      , stepId s /= consumer
      , possiblyBefore (planOrder plan) (stepId s) consumer
      , e <- stepEff s
      , Just b' <- [unifyLiterals b e p]
      ]
    closedWorld =
      [ Establisher plan initStepId False
      | not (litPositive p)
      , let a = resolveAtom b (litAtom p)
      , not (any (\i -> unifyAtoms b i a /= Nothing) (Set.toList (envInit env)))
      ]
    new =
      [ est
      | (g, e) <- Map.findWithDefault [] (litPositive p, atomPredicate (litAtom p)) (envEffectIndex env)
      , let k = planNextStep plan
      , Just b' <- [unifyLiterals b (instantiateLiteral k e) p]
      , Just est <- [addStep g k plan {planBindings = b'}]
      ]

-- | Insert a new Step for a ground action, with its open conditions.
addStep :: GroundAction -> StepId -> Plan -> Maybe Establisher
addStep g k plan = do
  b <- foldM (\acc (x, y) -> addNeq acc (instantiateTerm k x) (instantiateTerm k y)) (planBindings plan) (gaNeq g)
  o <- addOrder initStepId k (planOrder plan) >>= addOrder k goalStepId
  let step =
        Step
          { stepId = k
          , stepAction = Just g
          , stepArgs = map (instantiateTerm k) (gaArgs g)
          , stepActors = gaActors g
          , stepHappening = gaHappening g
          , stepPre = map (instantiateLiteral k) (gaPre g)
          , stepEff = map (instantiateLiteral k) (gaEff g)
          }
  Just
    Establisher
      { estPlan =
          plan
            { planSteps = IM.insert k step (planSteps plan)
            , planBindings = b
            , planOrder = o
            , planOpenConds = [(k, q) | q <- stepPre step] ++ planOpenConds plan
            , planNextStep = k + 1
            }
      , estStep = k
      , estNew = True
      }

tshow :: (Show a) => a -> Text
tshow = T.pack . show
