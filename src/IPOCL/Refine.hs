-- | Plan refinement: flaw detection and the refinement operators of Fig. 5.
module IPOCL.Refine
  ( Env (..)
  , mkEnv
  , mkEnvWith
  , Child (..)
  , Expansion (..)
  , flaws
  , causalThreats
  , causalThreatsFromScratch
  , isThreat
  , expand
  , refine
  ) where

import Control.Monad (foldM)
import Data.IntMap.Strict qualified as IM
import Data.IntSet qualified as IS
import Data.List (nub, sortOn)
import Data.Maybe (isJust, isNothing)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Ord (Down (..))
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
  , envActions :: ![GroundAction]
  , envEffectIndex :: !(Map (Bool, Text) [(GroundAction, Literal)])
  , envAttemptIndex :: Map (Bool, Text) [(GroundAction, Literal)]
  -- ^ Like 'envEffectIndex' over every ground action, reachable or not: an
  -- attempt may be blocked by a precondition nothing can achieve. Lazy.
  , envInit :: !(Set Atom)
  , envPrune :: Plan -> Bool
  -- ^ Hard pruning (e.g. hard Author preferences); 'True' drops the plan.
  }

mkEnv :: Problem -> Env
mkEnv p = mkEnvWith p (groundActions p)

mkEnvWith :: Problem -> [GroundAction] -> Env
mkEnvWith p gas =
  Env
    { envProblem = p
    , envActions = gas
    , envEffectIndex = effectIndex gas
    , envAttemptIndex = effectIndex (groundActions p)
    , envInit = problemInit p
    , envPrune = hardViolated p (problemPreferences p)
    }

effectIndex :: [GroundAction] -> Map (Bool, Text) [(GroundAction, Literal)]
effectIndex gas = Map.fromListWith (flip (++)) [((litPositive e, atomPredicate (litAtom e)), [(g, e)]) | g <- gas, e <- gaEff g]

data Child = Child {childPlan :: !Plan, childReason :: !Text}

data Expansion
  = Solution
  | DeadEnd !(Maybe Flaw)
  -- ^ The flaw that cannot be repaired, or 'Nothing' for a flawless plan with
  -- Orphans or a broken hard relevance preference.
  | Refined !Flaw ![Child]

-- | All flaws of a plan: threats first, then the rest in tie-break order.
flaws :: Plan -> [Flaw]
flaws plan =
  causalThreats plan
    ++ intentionalThreats plan
    ++ [OpenMotivation (frameId f) | f <- IM.elems (planFrames plan), isNothing (frameMotivator f)]
    ++ [OpenAttempt s | s <- planOpenAttempts plan]
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
expand env plan = case flaws plan of
  []
    | not (null (orphans plan)) -> DeadEnd Nothing
    | finalViolated (envProblem env) (problemPreferences (envProblem env)) plan -> DeadEnd Nothing
    | otherwise -> Solution
  f : _ | isThreat f -> result f (refine env plan f)
  fs -> case sortOn fst [((estimate fl, i), fl) | (i, fl) <- zip [0 :: Int ..] fs] of
    (_, f) : _ -> result f (refine env plan f)
    [] -> Solution
  where
    result f [] = DeadEnd (Just f)
    result f cs = Refined f cs
    estimate = refinementEstimate env plan

-- | An upper bound on a flaw's number of children, cheap enough to compute for
-- every flaw. Any flaw with no children makes the plan a dead end, so ranking
-- by the estimate and refining only the winner loses no solutions.
refinementEstimate :: Env -> Plan -> Flaw -> Int
refinementEstimate env plan = \case
  OpenCondition s p -> length (establishers env plan [s] p)
  OpenMotivation c -> case IM.lookup c (planFrames plan) of
    Just f -> length (establishers env plan (IS.toList (frameInterval f)) (frameIntention f))
    Nothing -> 0
  IntentFlaw {} -> 2
  CausalThreat {} -> 3
  IntentionalThreat {} -> 2
  OpenAttempt s -> length (openAttempt env plan s)

refine :: Env -> Plan -> Flaw -> [Child]
refine env plan = \case
  OpenCondition s p -> openCondition env plan s p
  CausalThreat t l -> resolveCausalThreat env plan t l
  OpenMotivation c -> openMotivation env plan c
  IntentFlaw s c -> resolveIntentFlaw env plan s c
  IntentionalThreat a b -> resolveIntentionalThreat env plan a b
  OpenAttempt s -> openAttempt env plan s

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

-- | The plan's causal threats, as kept up to date by 'withLinkThreats',
-- 'withStepThreats' and 'recheckThreats'.
causalThreats :: Plan -> [Flaw]
causalThreats plan = [CausalThreat t l | (l, Down t) <- Set.toList (planThreats plan)]

-- | Steps that may fall inside a causal link and assert the negation of its
-- condition, computed from scratch: the oracle for 'causalThreats'.
causalThreatsFromScratch :: Plan -> [Flaw]
causalThreatsFromScratch plan =
  [ CausalThreat (stepId t) l
  | l <- Set.toList (planLinks plan)
  , let clobber = negateLit (linkCond l)
  , t <- Map.findWithDefault [] (litKey clobber) clobberers
  , threatens plan l t
  ]
  where
    clobberers = Map.fromListWith (++) [(k, [t]) | t <- planStepList plan, k <- nub (map litKey (stepEff t))]

litKey :: Literal -> (Bool, Text)
litKey l = (litPositive l, atomPredicate (litAtom l))

-- | @t@ may fall inside @l@ and assert the negation of its condition. Adding
-- orderings or bindings can only make this false, never true. An attempted Step
-- has no effects, so it threatens nothing.
threatens :: Plan -> CausalLink -> Step -> Bool
threatens plan l t =
  stepId t /= linkFrom l
    && stepId t /= linkTo l
    && not (isUnexecuted plan (stepId t))
    && possiblyBefore o (linkFrom l) (stepId t)
    && possiblyBefore o (stepId t) (linkTo l)
    && any (\e -> litKey e == litKey clobber && isJust (unifyLiterals (planBindings plan) e clobber)) (stepEff t)
  where
    o = planOrder plan
    clobber = negateLit (linkCond l)

-- | Record the threats to a newly added link.
withLinkThreats :: CausalLink -> Plan -> Plan
withLinkThreats l plan =
  plan {planThreats = foldr Set.insert (planThreats plan) [(l, Down (stepId t)) | t <- planStepList plan, threatens plan l t]}

-- | Record the threats a newly added Step poses to existing links.
withStepThreats :: StepId -> Plan -> Plan
withStepThreats s plan = case IM.lookup s (planSteps plan) of
  Nothing -> plan
  Just t -> plan {planThreats = foldr Set.insert (planThreats plan) [(l, Down s) | l <- Set.toList (planLinks plan), threatens plan l t]}

-- | Drop recorded threats that orderings or bindings have since ruled out.
recheckThreats :: Plan -> Plan
recheckThreats plan = plan {planThreats = Set.filter stillThreat (planThreats plan)}
  where
    stillThreat (l, Down s) = maybe False (threatens plan l) (IM.lookup s (planSteps plan))

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
      [ p'
      | Just step <- [IM.lookup t (planSteps plan)]
      , e <- map (resolveLiteral b) (stepEff step)
      , litPositive e == litPositive cond
      , isJust (unifyLiterals b e cond)
      , e /= cond
      , (x, y) <- zip (atomArgs (litAtom e)) (atomArgs (litAtom cond))
      , x /= y
      , Just b' <- [addNeq b x y]
      , Just p' <- [keep env plan {planBindings = b'}]
      ]

-- Causal planning ---------------------------------------------------------

openCondition :: Env -> Plan -> StepId -> Literal -> [Child]
openCondition env plan0 sNeed p =
  [ Child plan' (establishReason plan' est p <> note)
  | est <- establishers env plan [sNeed] p
  , Just linked <- [link est]
  , (plan', note) <- afterEstablish env est linked
  , fulfils plan' (estStep est)
  ]
  where
    plan = plan0 {planOpenConds = filter (/= (sNeed, p)) (planOpenConds plan0)}
    -- A Required Frame's pseudo-step is supported only by the final Step of a
    -- Frame of its Character for this goal (ADR-0004).
    fulfils pl sAdd = case IM.lookup sNeed (planRequired pl) of
      Just c -> any (\f -> frameFinal f == Just sAdd && resolvedGoal pl f == resolveLiteral (planBindings pl) p) (framesOf pl c)
      Nothing -> True
    link (Establisher pl sAdd _) = do
      o <- addOrder sAdd sNeed (planOrder pl)
      let l = CausalLink sAdd p sNeed
      Just (withLinkThreats l pl {planOrder = o, planLinks = Set.insert l (planLinks pl)})

-- Motivation planning -------------------------------------------------------

-- | Find a Motivating step for a Frame and order it before the whole Interval.
openMotivation :: Env -> Plan -> FrameId -> [Child]
openMotivation env plan fid = case IM.lookup fid (planFrames plan) of
  Nothing -> []
  Just f ->
    let members = IS.toList (frameInterval f)
        motivate (Establisher pl m _) = do
          o <- foldM (flip (addOrder m)) (planOrder pl) members
          Just pl {planOrder = o, planFrames = IM.insert fid f {frameMotivator = Just m} (planFrames pl)}
     in [ Child plan' (establishReason plan' est (frameIntention f) <> note)
        | est <- establishers env plan members (frameIntention f)
        , Just motivated <- [motivate est]
        , (plan', note) <- afterEstablish env est motivated
        ]

-- Attempt planning ------------------------------------------------------------

-- | Give a ':fail-first' Required Frame its failed Frame (ADR-0003): a new,
-- unexecuted Step that would achieve the goal for the Character, with exactly
-- one precondition replaced by an open condition for its negation.
openAttempt :: Env -> Plan -> StepId -> [Child]
openAttempt env plan0 ps = case (IM.lookup ps (planRequired plan), IM.lookup ps (planSteps plan)) of
  (Just c, Just pseudo)
    | [g] <- stepPre pseudo
    , not (any (\f -> isNothing (frameFinal f) && resolvedGoal plan f == g) (framesOf plan c)) ->
        [ Child pl' ("attempt " <> stepLabel pl' st <> " by " <> symbolText c <> ", blocked by " <> prettyLiteral (resolveLiteral (planBindings pl') (negateLit q)))
        | let k = planNextStep plan
        , (ga, e) <- Map.findWithDefault [] (litPositive g, atomPredicate (litAtom g)) (envAttemptIndex env)
        , not (gaHappening ga)
        , c `elem` gaActors ga
        , Just b' <- [unifyLiterals (planBindings plan) (instantiateLiteral k e) g]
        , Just est <- [addStep ga k plan {planBindings = b'}]
        , Just st <- [IM.lookup k (planSteps (estPlan est))]
        , q <- nub (stepPre st)
        , Just pl' <- [finalize env (attempt (estPlan est) k c g q)]
        ]
  _ -> []
  where
    plan = plan0 {planOpenAttempts = filter (/= ps) (planOpenAttempts plan0)}
    attempt pl k c g q =
      let fid = planNextFrame pl
       in pl
            { planOpenConds = map (\oc -> if oc == (k, q) then (k, negateLit q) else oc) (planOpenConds pl)
            , planUnexecuted = IS.insert k (planUnexecuted pl)
            , planFrames = IM.insert fid (Frame fid c g Nothing (IS.singleton k) Nothing (Just k)) (planFrames pl)
            , planNextFrame = fid + 1
            , planFailFirst = IM.insert ps fid (planFailFirst pl)
            }

-- | Order each failed Frame entirely before the successful Frame that fulfils
-- the same ':fail-first' Required Frame, once both exist; 'Nothing' if they
-- cannot be ordered that way.
orderFailFirst :: Plan -> Maybe Plan
orderFailFirst plan0 = foldM one plan0 (IM.toList (planFailFirst plan0))
  where
    one pl (ps, ff) = case (IM.lookup ff (planFrames pl), successOf pl ps) of
      (Just failed, Just sf)
        | not (Set.member (ff, frameId sf) (planFrameOrder pl)) -> do
            o <- foldM (\acc (x, y) -> addOrder x y acc) (planOrder pl) [(x, y) | x <- IS.toList (frameInterval failed), y <- IS.toList (frameInterval sf)]
            Just pl {planOrder = o, planFrameOrder = Set.insert (ff, frameId sf) (planFrameOrder pl)}
      _ -> Just pl
    successOf pl ps =
      case [f | l <- Set.toList (planLinks pl), linkTo l == ps, f <- IM.elems (planFrames pl), frameFinal f == Just (linkFrom l)] of
        f : _ -> Just f
        [] -> Nothing

-- Shared by causal and motivation planning: frame discovery on new Steps,
-- then bookkeeping and pruning.
afterEstablish :: Env -> Establisher -> Plan -> [(Plan, Text)]
afterEstablish env est pl0 =
  [ (pl'', note)
  | (pl', note) <- if estNew est then discoverFrames (estStep est) pl else [(pl, "")]
  , Just pl'' <- [finalize env pl']
  ]
  where
    -- Not done in 'addStep': flaw ranking builds establishers it never keeps.
    pl = if estNew est then withStepThreats (estStep est) pl0 else pl0

-- | Bookkeeping after every refinement: prune, then propose new intent flaws.
-- Hard preferences never read the intent fields, so pruning first is safe.
finalize :: Env -> Plan -> Maybe Plan
finalize env pl0 = do
  pl <- orderFailFirst pl0 >>= keep env
  let fresh = nub [c | c <- intentCandidates pl, not (Set.member c (planProposedIntent pl))]
  Just
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
      Just st -> not (stepHappening st) && not (isUnexecuted plan s) && frameCharacter c `elem` stepActors st && not (IS.member s (frameInterval c))
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
              ++ [(s, fin) | Just fin <- [frameEnd f], fin /= s]
              ++ [(s, x) | (a, later) <- frameOrder, a == c, x <- members later]
              ++ [(x, s) | (earlier, b) <- frameOrder, b == c, x <- members earlier]
      o <- foldM (\acc (x, y) -> addOrder x y acc) (planOrder plan) orderings
      finalize env plan {planOrder = o, planFrames = IM.insert c f {frameInterval = IS.insert s (frameInterval f)} (planFrames plan)}

-- | Every child passes through here, so it is where recorded threats are
-- re-checked against the child's new orderings and bindings. A child with a
-- threat that no ordering or separation can repair is dropped now rather than
-- expanded into a dead end.
keep :: Env -> Plan -> Maybe Plan
keep env pl
  | envPrune env pl = Nothing
  | all (repairable checked) (Set.toList (planThreats checked)) = Just checked
  | otherwise = Nothing
  where
    checked = recheckThreats pl

-- | Some promotion, demotion or separation of the threat is consistent.
repairable :: Plan -> (CausalLink, Down StepId) -> Bool
repairable plan (l, Down t) =
  isJust (addOrder (linkTo l) t o)
    || isJust (addOrder t (linkFrom l) o)
    || not (null separations)
  where
    o = planOrder plan
    b = planBindings plan
    cond = resolveLiteral b (negateLit (linkCond l))
    separations =
      [ ()
      | Just step <- [IM.lookup t (planSteps plan)]
      , e <- map (resolveLiteral b) (stepEff step)
      , litPositive e == litPositive cond
      , isJust (unifyLiterals b e cond)
      , e /= cond
      , (x, y) <- zip (atomArgs (litAtom e)) (atomArgs (litAtom cond))
      , x /= y
      , Just _ <- [addNeq b x y]
      ]

-- Frame discovery -------------------------------------------------------------

-- | For a new non-Happening Step, each Actor independently either intends one
-- of the Step's effects (a new Frame with this Step as its final Step) or not.
discoverFrames :: StepId -> Plan -> [(Plan, Text)]
discoverFrames s plan = case IM.lookup s (planSteps plan) of
  Just st | not (stepHappening st) -> foldM (choose st) (plan, "") (stepActors st)
  _ -> [(plan, "")]
  where
    choose st (pl, note) actor =
      (pl, note)
        : [ (pl', note <> "; " <> symbolText actor <> " intends " <> prettyLiteral (resolveLiteral (planBindings pl) e))
          | e <- stepEff st
          , Just pl' <- [newFrame pl actor e]
          ]
    newFrame pl actor e
      | any (\f -> isJust (frameFinal f) && resolvedGoal pl f == resolveLiteral (planBindings pl) e) (framesOf pl actor) = Nothing
      | otherwise =
          let k = planNextFrame pl
              f = Frame k actor e (Just s) (IS.singleton s) Nothing Nothing
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
establishers env plan later p = existing ++ closedWorld ++ backstory ++ new
  where
    b = planBindings plan
    candidates = problemBackstory (envProblem env)
    existing =
      [ Establisher plan {planBindings = b'} (stepId s) False
      | s <- planStepList plan
      , not (isUnexecuted plan (stepId s))
      , all (possiblyBefore (planOrder plan) (stepId s)) later
      , e <- stepEff s
      , Just b' <- [unifyLiterals b e p]
      ]
    -- Possible backstory is unknown rather than false until committed.
    closedWorld =
      [ Establisher plan initStepId False
      | not (litPositive p)
      , let a = resolveAtom b (litAtom p)
      , not (any (\i -> isJust (unifyAtoms b i a)) (Set.toList (envInit env) ++ candidates))
      ]
    backstory =
      [ Establisher (commit a plan {planBindings = b'}) initStepId False
      | litPositive p
      , a <- candidates
      , not (Set.member a (planBackstory plan))
      , Just b' <- [unifyAtoms b a (litAtom p)]
      , not (any (deniedBy b' a) (Set.toList (planLinks plan)))
      ]
    deniedBy b' a l = linkFrom l == initStepId && not (litPositive (linkCond l)) && isJust (unifyAtoms b' a (litAtom (linkCond l)))
    commit a pl =
      pl
        { planBackstory = Set.insert a (planBackstory pl)
        , planSteps = IM.adjust (\s -> s {stepEff = pos a : stepEff s}) initStepId (planSteps pl)
        }
    new =
      [ est
      | let k = planNextStep plan
      , (g, e) <- Map.findWithDefault [] (litPositive p, atomPredicate (litAtom p)) (envEffectIndex env)
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
