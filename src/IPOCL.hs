-- | Public planner API: turn a Problem into Stories.
module IPOCL
  ( SolveConfig (..)
  , defaultSolveConfig
  , Outcome (..)
  , Result (..)
  , solve
  , solvePure
  , HeuristicChoice (..)
  , module IPOCL.Plan
  ) where

import Data.IORef
import GHC.Clock (getMonotonicTime)
import IPOCL.Ground
import IPOCL.Heuristic
import IPOCL.Plan
import IPOCL.Preferences (softPenalty)
import IPOCL.Refine
import IPOCL.Search
import IPOCL.Syntax

data SolveConfig = SolveConfig
  { cfgMode :: !Mode
  , cfgMaxExpanded :: !(Maybe Int)
  , cfgTimeout :: !(Maybe Double)
  -- ^ Seconds of wall-clock time.
  , cfgCount :: !Int
  -- ^ How many Stories to return.
  , cfgTrace :: !(Maybe (SearchEvent -> IO ()))
  , cfgHeuristic :: !HeuristicChoice
  , cfgWeight :: !Double
  -- ^ Weight on @h@ in weighted A*.
  , cfgGreedy :: !Bool
  -- ^ Ignore @g@ entirely.
  , cfgMaxGenerated :: !(Maybe Int)
  }

defaultSolveConfig :: SolveConfig
defaultSolveConfig =
  SolveConfig
    { cfgMode = IPOCL
    , cfgMaxExpanded = Just 200000
    , cfgTimeout = Nothing
    , cfgCount = 1
    , cfgTrace = Nothing
    , cfgHeuristic = Additive
    , cfgWeight = 2
    , cfgGreedy = False
    , cfgMaxGenerated = Nothing
    }

data Outcome = Solved | Exhausted | LimitHit
  deriving (Eq, Show)

data Result = Result
  { resultOutcome :: !Outcome
  , resultStories :: ![Plan]
  , resultExpanded :: !Int
  , resultGenerated :: !Int
  }

events :: SolveConfig -> Problem -> [SearchEvent]
events cfg p = search env searchCfg (initialPlan p)
  where
    r = reachability (problemInit p) (groundActions p)
    env = mkEnvWith (cfgMode cfg) p (reachableActions r)
    searchCfg =
      defaultSearchConfig
        { scWeight = cfgWeight cfg
        , scGreedy = cfgGreedy cfg
        , scHeuristic = \plan -> (+ softPenalty (problemPreferences p) plan) <$> heuristic (cfgHeuristic cfg) r env plan
        , scCost = case cfgHeuristic cfg of
            Blind -> const
            _ -> scCost defaultSearchConfig
        }

-- | Solve without time-outs or tracing.
solvePure :: SolveConfig -> Problem -> Result
solvePure cfg p = go 0 0 [] (events cfg p)
  where
    go expanded generated found = \case
      [] -> Result (if null found then Exhausted else Solved) (reverse found) expanded generated
      ev : rest -> case ev of
        FoundSolution _ plan ->
          let found' = plan : found
           in if length found' >= cfgCount cfg
                then Result Solved (reverse found') expanded generated
                else go expanded generated found' rest
        Visited {evChildren = n}
          | Just m <- cfgMaxExpanded cfg, expanded >= m -> Result LimitHit (reverse found) expanded generated
          | otherwise -> go (expanded + 1) (generated + n) found rest

-- | Solve, honouring the time-out and streaming trace events.
solve :: SolveConfig -> Problem -> IO Result
solve cfg p = do
  start <- getMonotonicTime
  foundRef <- newIORef []
  let finish o e g = do
        found <- readIORef foundRef
        pure (Result o (reverse found) e g)
      go expanded generated = \case
        [] -> do
          found <- readIORef foundRef
          finish (if null found then Exhausted else Solved) expanded generated
        ev : rest -> do
          mapM_ ($ ev) (cfgTrace cfg)
          case ev of
            FoundSolution _ plan -> do
              modifyIORef' foundRef (plan :)
              n <- length <$> readIORef foundRef
              if n >= cfgCount cfg then finish Solved expanded generated else go expanded generated rest
            Visited {evChildren = k} -> do
              now <- getMonotonicTime
              let overTime = maybe False (\t -> now - start > t) (cfgTimeout cfg)
                  overNodes = maybe False (expanded >=) (cfgMaxExpanded cfg)
              if overTime || overNodes
                then finish LimitHit expanded generated
                else go (expanded + 1) (generated + k) rest
  go 0 0 (events cfg p)
