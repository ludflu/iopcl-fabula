-- | Plan refinement: flaw detection and the refinement operators of Fig. 5.
module IPOCL.Refine
  ( Env (..)
  , mkEnv
  , mkEnvWith
  , Child (..)
  , Expansion (..)
  , flaws
  , expand
  , refine
  ) where

import Control.Monad (foldM)
import Data.IntMap.Strict qualified as IM
import Data.IntSet qualified as IS
import Data.List (nub, sortOn)
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
import IPOCL.Preferences
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
    , envPrune = hardViolated (problemPreferences p)
    }

data Child = Child {childPlan :: !Plan, childReason :: !Text}

data Expansion
  = Solution
  | DeadEnd !(Maybe Flaw)
  -- ^ The flaw that cannot be repaired, or 'Nothing' when only Orphans remain.
  | Refined !Flaw ![Child]

-- | All flaws of a plan: threats first, then the rest in tie-break order.
flaws :: Env -> Plan -> [Flaw]
flaws _ plan =
  causalThreats plan
    ++ intentionalThreats plan
    ++ [OpenMotivation (frameId f) | f <- IM.elems (planFrames plan), frameMotivator f == Nothing]
    ++ [OpenCondition s l | (s, l) <- planOpenConds plan]
    ++ [IntentFlaw s c | (s, c) <- planPendingIntent plan]

isThreat :: Flaw -> Bool
isThreat = \case
  CausalThreat {} -> True
  IntentionalThreat {} -> True
  _ -> False

-- | Select a flaw and produce its children, or recognise a solution / dead end.
-- Threats are repaired first; otherwise the flaw with the fewest children.
expand :: Env -> Plan -> Expansion
expand env plan = case flaws env plan of
  []
    | envMode env == IPOCL && not (null (orphans plan)) -> DeadEnd Nothing
    | otherwise -> Solution
  f : _ | isThreat f -> result f (refine env plan f)
  fs ->
    let scored = [(length kids, i, fl, kids) | (i, fl) <- zip [0 :: Int ..] fs, let kids = refine env plan fl]
     in case sortOn (\(k, i, _, _) -> (k, i)) scored of
          (_, _, f, cs) : _ -> result f cs
          [] -> Solution
  where
    result f [] = DeadEnd (Just f)
    result f cs = Refined f cs

refine :: Env -> Plan -> Flaw -> [Child]
refine env plan = \case
  OpenCondition s p -> openCondition env plan s p
  CausalThreat t l -> resolveCausalThreat env plan t l
  OpenMotivation c -> openMotivation env plan c
  IntentFlaw s c -> resolveIntentFlaw env plan s c
  IntentionalThreat a b -> resolveIntentionalThreat env plan a b

-- Intentional threats -------------------------------------------------------

-- | Unordered Frames of one Character whose Character goals necessarily negate
-- each other (Def. 9).
intentionalThreats :: Plan -> [Flaw]
intentionalThreats plan =
  [ IntentionalThreat (frameId a) (frameId b)
  | a <- fs
  , b <- fs
  , frameId a < frameId b
  , frameCharacter a == frameCharacter b
  , not (Set.member (frameId a, frameId b) (planFrameOrder plan))
  , not (Set.member (frameId b, frameId a) (planFrameOrder plan))
  , let ga = resolvedGoal plan a
        gb = resolvedGoal plan b
  , litPositive ga /= litPositive gb
  , litAtom ga == litAtom gb
  ]
  where
    fs = IM.elems (planFrames plan)

-- | Order one Frame's Interval entirely before the other's, either way round.
resolveIntentionalThreat :: Env -> Plan -> FrameId -> FrameId -> [Child]
resolveIntentionalThreat env plan a b =
  [Child p' ("frame " <> tshow x <> " before frame " <> tshow y) | (x, y) <- [(a, b), (b, a)], Just p' <- [orderFrames x y]]
  where
    members fid = maybe [] (IS.toList . frameInterval) (IM.lookup fid (planFrames plan))
    orderFrames x y = do
      o <- foldM (\acc (s, t) -> addOrder s t acc) (planOrder plan) [(s, t) | s <- members x, t <- members y]
      keep env plan {planOrder = o, planFrameOrder = Set.insert (x, y) (planFrameOrder plan)}

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
  [ Child plan' (establishReason plan' est p <> note)
  | est <- establishers env plan [sNeed] p
  , Just linked <- [link est]
  , (plan', note) <- afterEstablish env est linked
  ]
  where
    plan = plan0 {planOpenConds = filter (/= (sNeed, p)) (planOpenConds plan0)}
    link (Establisher pl sAdd _) = do
      o <- addOrder sAdd sNeed (planOrder pl)
      Just pl {planOrder = o, planLinks = Set.insert (CausalLink sAdd p sNeed) (planLinks pl)}

-- Motivation planning -------------------------------------------------------

-- | Find a Motivating step for a Frame and order it before the whole Interval.
openMotivation :: Env -> Plan -> FrameId -> [Child]
openMotivation env plan fid = case IM.lookup fid (planFrames plan) of
  Nothing -> []
  Just f ->
    let members = IS.toList (frameInterval f)
        motivate (Establisher pl m _) = do
          o <- foldM (\acc s -> addOrder m s acc) (planOrder pl) members
          Just pl {planOrder = o, planFrames = IM.insert fid f {frameMotivator = Just m} (planFrames pl)}
     in [ Child plan' (establishReason plan' est (frameIntention f) <> note)
        | est <- establishers env plan members (frameIntention f)
        , Just motivated <- [motivate est]
        , (plan', note) <- afterEstablish env est motivated
        ]

-- Shared by causal and motivation planning: frame discovery on new Steps,
-- then bookkeeping and pruning.
afterEstablish :: Env -> Establisher -> Plan -> [(Plan, Text)]
afterEstablish env est pl =
  [ (pl'', note)
  | (pl', note) <- if estNew est then discoverFrames env (estStep est) pl else [(pl, "")]
  , Just pl'' <- [finalize env pl']
  ]

-- | Bookkeeping after every refinement: propose new intent flaws, then prune.
finalize :: Env -> Plan -> Maybe Plan
finalize env pl
  | envMode env == POCL = keep env pl
  | otherwise =
      let fresh = nub [c | c <- intentCandidates pl, not (Set.member c (planProposedIntent pl))]
       in keep
            env
            pl
              { planPendingIntent = fresh ++ planPendingIntent pl
              , planProposedIntent = foldr Set.insert (planProposedIntent pl) fresh
              }

-- | Step-Frame pairs that could explain the Step (ADR-0002): the Step shares
-- the Frame's Character and either (1) causally supports a member of the
-- Interval, or (2) motivates another Frame whose final Step supports a member.
intentCandidates :: Plan -> [(StepId, FrameId)]
intentCandidates plan = cond1 ++ cond2
  where
    frames = IM.elems (planFrames plan)
    links = Set.toList (planLinks plan)
    eligible s c = case IM.lookup s (planSteps plan) of
      Just st -> not (stepHappening st) && frameCharacter c `elem` stepActors st && not (IS.member s (frameInterval c))
      Nothing -> False
    serves s c = any (\l -> linkFrom l == s && IS.member (linkTo l) (frameInterval c)) links
    cond1 = [(linkFrom l, frameId c) | l <- links, c <- frames, IS.member (linkTo l) (frameInterval c), eligible (linkFrom l) c]
    cond2 =
      [ (m, frameId c)
      | ci <- frames
      , Just m <- [frameMotivator ci]
      , m /= initStepId
      , Just fin <- [frameFinal ci]
      , c <- frames
      , frameId c /= frameId ci
      , eligible m c
      , serves fin c
      ]

-- Intent planning -------------------------------------------------------------

-- | Either adopt the Step into the Frame's Interval or leave it out.
resolveIntentFlaw :: Env -> Plan -> StepId -> FrameId -> [Child]
resolveIntentFlaw env plan0 s c =
  [Child p' ("adoption of step " <> tshow s <> " by frame " <> tshow c) | Just p' <- [adopt]]
    ++ [Child p' ("step " <> tshow s <> " stays out of frame " <> tshow c) | Just p' <- [keep env plan]]
  where
    plan = plan0 {planPendingIntent = filter (/= (s, c)) (planPendingIntent plan0)}
    adopt = do
      f <- IM.lookup c (planFrames plan)
      let members g = maybe [] (IS.toList . frameInterval) (IM.lookup g (planFrames plan))
          frameOrder = Set.toList (planFrameOrder plan)
          orderings =
            [(m, s) | Just m <- [frameMotivator f]]
              ++ [(s, fin) | Just fin <- [frameFinal f], fin /= s]
              ++ [(s, x) | (a, later) <- frameOrder, a == c, x <- members later]
              ++ [(x, s) | (earlier, b) <- frameOrder, b == c, x <- members earlier]
      o <- foldM (\acc (x, y) -> addOrder x y acc) (planOrder plan) orderings
      finalize env plan {planOrder = o, planFrames = IM.insert c f {frameInterval = IS.insert s (frameInterval f)} (planFrames plan)}

keep :: Env -> Plan -> Maybe Plan
keep env pl = if envPrune env pl then Nothing else Just pl

-- Frame discovery -------------------------------------------------------------

-- | For a new non-Happening Step, each Actor independently either intends one
-- of the Step's effects (a new Frame with this Step as its final Step) or not.
discoverFrames :: Env -> StepId -> Plan -> [(Plan, Text)]
discoverFrames env s plan = case IM.lookup s (planSteps plan) of
  Just st | envMode env == IPOCL, not (stepHappening st) -> foldM (choose st) (plan, "") (stepActors st)
  _ -> [(plan, "")]
  where
    choose st (pl, note) actor =
      (pl, note)
        : [ (pl', note <> "; " <> symbolText actor <> " intends " <> prettyLiteral (resolveLiteral (planBindings pl) e))
          | e <- stepEff st
          , Just pl' <- [newFrame pl actor e]
          ]
    newFrame pl actor e
      | any (\f -> resolvedGoal pl f == resolveLiteral (planBindings pl) e) (framesOf pl actor) = Nothing
      | otherwise =
          let k = planNextFrame pl
              f = Frame k actor e (Just s) (IS.singleton s) Nothing
           in Just pl {planFrames = IM.insert k f (planFrames pl), planNextFrame = k + 1}

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

-- | Ways to make @p@ true before all of @later@, via existing Steps (including
-- the initial state under the closed-world assumption) or a new Step.
establishers :: Env -> Plan -> [StepId] -> Literal -> [Establisher]
establishers env plan later p = existing ++ closedWorld ++ new
  where
    b = planBindings plan
    existing =
      [ Establisher plan {planBindings = b'} (stepId s) False
      | s <- planStepList plan
      , all (possiblyBefore (planOrder plan) (stepId s)) later
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
