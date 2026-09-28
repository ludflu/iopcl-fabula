module Main (main) where

import Control.Monad (forM_, unless, when)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import IPOCL
import IPOCL.DomainCheck
import IPOCL.Domains.Aladdin
import IPOCL.Domains.Bribe
import IPOCL.Domains.Tiny
import IPOCL.Domains.Tower
import IPOCL.Parser
import IPOCL.Report
import IPOCL.Syntax
import IPOCL.Validate
import Options.Applicative
import System.Exit (exitFailure)
import System.IO (stderr)

data Command
  = Builtin Text SolveOpts
  | SolveFiles FilePath FilePath SolveOpts

data SolveOpts = SolveOpts
  { optMode :: Mode
  , optMaxNodes :: Maybe Int
  , optTimeout :: Maybe Double
  , optCount :: Int
  }

builtins :: [(Text, Problem)]
builtins =
  [ ("tiny", tinyProblem)
  , ("tower", towerProblem)
  , ("motivated-tower", motivatedTowerProblem)
  , ("bribe", bribeProblem)
  , ("aladdin", aladdinProblem)
  ]

solveOpts :: Parser SolveOpts
solveOpts =
  SolveOpts
    <$> option (eitherReader readMode) (long "mode" <> metavar "ipocl|pocl" <> value IPOCL <> help "Planning mode (default ipocl)")
    <*> optional (option auto (long "max-nodes" <> metavar "N" <> help "Maximum nodes to expand"))
    <*> optional (option auto (long "timeout" <> metavar "SECONDS" <> help "Wall-clock limit"))
    <*> option auto (long "count" <> metavar "N" <> value 1 <> help "Number of distinct stories")
  where
    readMode = \case
      "ipocl" -> Right IPOCL
      "pocl" -> Right POCL
      m -> Left ("unknown mode " <> m)

commandP :: Parser Command
commandP =
  hsubparser
    ( command "solve" (info (SolveFiles <$> strArgument (metavar "DOMAIN") <*> strArgument (metavar "PROBLEM") <*> solveOpts) (progDesc "Solve a problem read from domain and problem files"))
        <> command "builtin" (info (Builtin <$> strArgument (metavar "NAME" <> help (builtinHelp)) <*> solveOpts) (progDesc "Solve a built-in problem"))
    )
  where
    builtinHelp = "One of: " <> T.unpack (T.intercalate ", " (map fst builtins))

main :: IO ()
main = do
  cmd <- execParser (info (commandP <**> helper) (fullDesc <> progDesc "IPOCL narrative planner"))
  case cmd of
    Builtin name opts -> case lookup name builtins of
      Nothing -> die' ("unknown built-in problem " <> name)
      Just p -> run p opts
    SolveFiles domainFile problemFile opts ->
      loadProblem domainFile problemFile >>= either die' (`run` opts)

run :: Problem -> SolveOpts -> IO ()
run p opts = do
  let issues = checkProblem p
  unless (null issues) $ do
    mapM_ (TIO.hPutStrLn stderr) issues
    exitFailure
  let cfg =
        defaultSolveConfig
          { cfgMode = optMode opts
          , cfgMaxExpanded = maybe (cfgMaxExpanded defaultSolveConfig) Just (optMaxNodes opts)
          , cfgTimeout = optTimeout opts
          , cfgCount = optCount opts
          }
  r <- solve cfg p
  forM_ (zip [1 :: Int ..] (resultStories r)) $ \(i, plan) -> do
    TIO.putStrLn ("Story " <> T.pack (show i))
    TIO.putStr (renderPlan plan)
    let problems = validatePlan (optMode opts) p plan
    unless (null problems) $ do
      TIO.putStrLn "INVALID:"
      mapM_ (TIO.putStrLn . ("  " <>)) problems
  TIO.putStrLn
    ( T.pack (show (resultOutcome r))
        <> ": expanded "
        <> T.pack (show (resultExpanded r))
        <> ", generated "
        <> T.pack (show (resultGenerated r))
    )
  when (null (resultStories r)) exitFailure

die' :: Text -> IO a
die' msg = TIO.hPutStrLn stderr msg >> exitFailure
