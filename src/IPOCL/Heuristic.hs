-- | Relaxed reachability over ground actions and the plan heuristics built on it.
module IPOCL.Heuristic
  ( Reachability
  , reachability
  , reachableActions
  , literalCost
  , uncachedLiteralCost
  , wantedLiterals
  , intentionCost
  , uncachedIntentionCost
  , HeuristicChoice (..)
  , heuristic
  , additiveHeuristic
  , paperHeuristic
  ) where

import Data.IntMap.Strict qualified as IM
import Data.Map.Lazy qualified as LazyMap
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, isNothing)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import IPOCL.Bindings
import IPOCL.Ground
import IPOCL.Plan
import IPOCL.Refine
import IPOCL.Syntax

-- | Additive (h_add) costs of reaching literals from the initial state,
-- ignoring delete interactions.
data Reachability = Reachability
  { rFacts :: !(Map Literal Int)
  , rByPredicate :: !(Map (Bool, Text) [(Literal, Int)])
  -- ^ Facts and lifted effect patterns, for literals that are not ground.
  , rInit :: !(Set Atom)
  , rActions :: ![GroundAction]
  , rGroundCosts :: Map Literal (Maybe Int)
  -- ^ Lazily memoised 'uncachedLiteralCost' for the ground literals plans ask for.
  , rIntentionCosts :: Map Symbol (Maybe Int)
  -- ^ Lazily memoised cheapest Intention per Actor.
  }

reachability :: Set Atom -> [GroundAction] -> Reachability
reachability initAtoms actions = r
  where
    r = Reachability facts byPred initAtoms reachable groundCosts intentionCosts
    groundCosts = LazyMap.fromSet (uncachedLiteralCost r) (Set.fromList (wantedLiterals reachable))
    intentionCosts = LazyMap.fromSet (uncachedIntentionCost r) (Set.fromList (concatMap gaActors reachable))
    initFacts = Map.fromList [(pos a, 0) | a <- Set.toList initAtoms]
    (facts, patterns, actionCost) = fixpoint initFacts Map.empty
    reachable = [g | g <- actions, Map.member (gaIndex g) actionCost]
    byPred =
      Map.fromListWith
        (++)
        ( [((litPositive l, atomPredicate (litAtom l)), [(l, c)]) | (l, c) <- Map.toList facts]
            ++ [((litPositive l, atomPredicate (litAtom l)), [(l, c)]) | (l, c) <- Map.toList patterns]
        )
    fixpoint fs costs =
      let lookupPre known ps l
            | not (isGroundLiteral l) = Just 0
            | otherwise = groundCost initAtoms known ps l
          pats0 = Map.empty :: Map Literal Int
          step (fsAcc, patsAcc, csAcc, changed) g =
            case traverse (lookupPre fsAcc patsAcc) (gaPre g) of
              Nothing -> (fsAcc, patsAcc, csAcc, changed)
              Just preCosts ->
                let c = 1 + sum preCosts
                    better m k = maybe True (> c) (Map.lookup k m)
                    (fs', ch1) = foldl' (\(m, ch) e -> if isGroundLiteral e && better m e then (Map.insert e c m, True) else (m, ch)) (fsAcc, False) (gaEff g)
                    (pats', ch2) = foldl' (\(m, ch) e -> if not (isGroundLiteral e) && better m e then (Map.insert e c m, True) else (m, ch)) (patsAcc, False) (gaEff g)
                    cs' = if maybe True (> c) (Map.lookup (gaIndex g) csAcc) then Map.insert (gaIndex g) c csAcc else csAcc
                 in (fs', pats', cs', changed || ch1 || ch2)
          loop (fsA, patsA, csA) =
            let (fs', pats', cs', changed) = foldl' step (fsA, patsA, csA, False) actions
             in if changed then loop (fs', pats', cs') else (fs', pats', cs')
       in loop (fs, pats0, costs)

-- | Cost of a ground literal from facts, the closed world, or lifted patterns.
groundCost :: Set Atom -> Map Literal Int -> Map Literal Int -> Literal -> Maybe Int
groundCost initAtoms facts patterns l =
  minimumMaybe (closedWorld ++ maybe [] pure (Map.lookup l facts) ++ fromPatterns)
  where
    closedWorld = [0 | not (litPositive l), not (Set.member (litAtom l) initAtoms)]
    fromPatterns = [c | (p, c) <- Map.toList patterns, isJust (unifyLiterals emptyBindings p l)]

minimumMaybe :: [Int] -> Maybe Int
minimumMaybe [] = Nothing
minimumMaybe xs = Just (minimum xs)

reachableActions :: Reachability -> [GroundAction]
reachableActions = rActions

-- | Ground literals a plan can ask for: preconditions of reachable actions,
-- and the Intentions behind Frames whose Character goal is a ground effect.
wantedLiterals :: [GroundAction] -> [Literal]
wantedLiterals gas =
  [l | g <- gas, l <- gaPre g, isGroundLiteral l]
    ++ [ pos (Atom intendsPredicate [TSym a, TLit e])
       | g <- gas
       , a <- gaActors g
       , e <- gaEff g
       , isGroundLiteral e
       ]

-- | Estimated cost of making a literal true; 'Nothing' if it is unreachable.
literalCost :: Reachability -> Bindings -> Literal -> Maybe Int
literalCost r b l0
  | isGroundLiteral l = fromMaybe (uncachedLiteralCost r l) (Map.lookup l (rGroundCosts r))
  | otherwise = uncachedLiteralCost r l
  where
    l = resolveLiteral b l0

-- | 'literalCost' for a resolved literal, without the memo table.
uncachedLiteralCost :: Reachability -> Literal -> Maybe Int
uncachedLiteralCost r l
  | isGroundLiteral l =
      minimumMaybe
        ( [0 | not (litPositive l), not (Set.member (litAtom l) (rInit r))]
            ++ maybe [] pure (Map.lookup l (rFacts r))
            ++ [c | (p, c) <- candidates, not (isGroundLiteral p), isJust (unifyLiterals emptyBindings p l)]
        )
  | otherwise =
      minimumMaybe
        ( [0 | not (litPositive l)]
            ++ [c | (p, c) <- candidates, isJust (unifyLiterals emptyBindings p l)]
        )
  where
    candidates = Map.findWithDefault [] (litPositive l, atomPredicate (litAtom l)) (rByPredicate r)

-- | Cheapest cost of giving an Actor any Intention at all.
intentionCost :: Reachability -> Symbol -> Maybe Int
intentionCost r a = fromMaybe (uncachedIntentionCost r a) (Map.lookup a (rIntentionCosts r))

uncachedIntentionCost :: Reachability -> Symbol -> Maybe Int
uncachedIntentionCost r a = uncachedLiteralCost r (pos (Atom intendsPredicate [TSym a, TVar (Var "anything" (-1))]))

data HeuristicChoice = Additive | Paper | Blind
  deriving (Eq, Show)

heuristic :: HeuristicChoice -> Reachability -> Env -> Plan -> Maybe Int
heuristic = \case
  Additive -> additiveHeuristic
  Paper -> const paperHeuristic
  Blind -> \_ _ _ -> Just 0

-- | Sum of reachability costs of what the plan still needs; 'Nothing' when
-- some open condition, open motivation or Orphan can never be repaired.
additiveHeuristic :: Reachability -> Env -> Plan -> Maybe Int
additiveHeuristic r env plan = do
  opens <- traverse (\(_, l) -> literalCost r b l) (planOpenConds plan)
  motivations <- traverse (\f -> (1 +) <$> literalCost r b (frameIntention f)) unmotivated
  orphanCosts <- traverse orphanCost (intentionalOrphans env plan)
  Just (sum opens + sum motivations + sum orphanCosts + length (planPendingIntent plan) + length threats)
  where
    b = planBindings plan
    unmotivated = [f | f <- IM.elems (planFrames plan), isNothing (frameMotivator f)]
    threats = filter isThreat (flaws env plan)
    -- An Orphan with a pending intent flaw for one of its Actor's Frames is one
    -- decision from joining; any other still needs a Frame it has not got.
    orphanCost (s, a)
      | any (\(s', c) -> s' == s && fmap frameCharacter (IM.lookup c (planFrames plan)) == Just a) (planPendingIntent plan) = Just 1
      | otherwise = (2 +) <$> intentionCost r a

-- | Orphans only exist when planning for intentionality.
intentionalOrphans :: Env -> Plan -> [(StepId, Symbol)]
intentionalOrphans env plan = if envMode env == IPOCL then orphans plan else []

-- | The domain-independent heuristic of Appendix A.1.
paperHeuristic :: Env -> Plan -> Maybe Int
paperHeuristic env plan =
  Just $
    length (actionSteps plan)
      + length (flaws env plan)
      + sum [10 * n | c <- characters, let n = length (framesOf plan c), n > 1]
      + 1000 * length [() | (_, a) <- intentionalOrphans env plan, null (framesOf plan a)]
  where
    characters = Set.toList (Set.fromList (map frameCharacter (IM.elems (planFrames plan))))
