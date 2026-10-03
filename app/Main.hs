module Main (main) where

import Control.Monad (forM_, unless, when)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import IPOCL
import IPOCL.Cards
import IPOCL.Lint
import IPOCL.DomainCheck
import IPOCL.Domains.Aladdin
import IPOCL.Domains.Bribe
import IPOCL.Domains.Tiny
import IPOCL.Domains.Tower
import IPOCL.Dot
import IPOCL.Narrate
import IPOCL.Parser
import IPOCL.Report
import IPOCL.Syntax
import IPOCL.Trace
import IPOCL.Validate
import Options.Applicative
import System.Directory (createDirectoryIfMissing)
import System.Exit (exitFailure)
import System.FilePath ((</>))
import System.IO (IOMode (WriteMode), stderr, withFile)

data Command
  = Builtin Text SolveOpts
  | SolveFiles FilePath FilePath SolveOpts
  | StoryGenius FilePath (Maybe FilePath) SolveOpts (Maybe FilePath)

data SolveOpts = SolveOpts
  { optMaxNodes :: Maybe Int
  , optTimeout :: Maybe Double
  , optCount :: Int
  , optTrace :: Maybe FilePath
  , optHeuristic :: HeuristicChoice
  , optWeight :: Double
  , optGreedy :: Bool
  , optSeed :: Int
  , optDedupe :: Bool
  , optNarrate :: Bool
  , optCards :: Bool
  , optDot :: Maybe FilePath
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
    <$> optional (option auto (long "max-nodes" <> metavar "N" <> help "Maximum nodes to expand"))
    <*> optional (option auto (long "timeout" <> metavar "SECONDS" <> help "Wall-clock limit"))
    <*> option auto (long "count" <> metavar "N" <> value 1 <> help "Number of distinct stories")
    <*> optional (strOption (long "trace" <> metavar "FILE" <> help "Write a search trace to FILE"))
    <*> option (eitherReader readHeuristic) (long "heuristic" <> metavar "default|paper|blind" <> value Additive <> help "Search heuristic")
    <*> option auto (long "weight" <> metavar "W" <> value 2 <> help "Weight on the heuristic in weighted A* (default 2)")
    <*> switch (long "greedy" <> help "Greedy best-first: ignore the cost so far")
    <*> option auto (long "seed" <> metavar "N" <> value 0 <> help "Seed for breaking ties between equally good plans")
    <*> switch (long "dedupe" <> help "Drop plans already reached by another refinement order")
    <*> (not <$> switch (long "no-narrate" <> help "Do not print the narration"))
    <*> switch (long "cards" <> help "Print a Story Genius scene card for each Step")
    <*> optional (strOption (long "dot" <> metavar "FILE" <> help "Write Story 1 as Graphviz to FILE; Story N>1 goes to FILE with -N before the extension"))
  where
    readHeuristic = \case
      "default" -> Right Additive
      "paper" -> Right Paper
      "blind" -> Right Blind
      h -> Left ("unknown heuristic " <> h)

commandP :: Parser Command
commandP =
  hsubparser
    ( command "solve" (info (SolveFiles <$> strArgument (metavar "DOMAIN") <*> strArgument (metavar "PROBLEM") <*> solveOpts) (progDesc "Solve a problem read from domain and problem files"))
        <> command "builtin" (info (Builtin <$> strArgument (metavar "NAME" <> help builtinHelp) <*> solveOpts) (progDesc "Solve a built-in problem"))
        <> command
          "story-genius"
          ( info
              ( StoryGenius
                  <$> strArgument (metavar "NAME|DOMAIN" <> help "Short name (e.g. misbelief) or path to a domain file")
                  <*> optional (strArgument (metavar "PROBLEM" <> help "Problem file when the first argument is a domain path"))
                  <*> solveOpts
                  <*> optional (strOption (long "output-dir" <> metavar "DIR" <> help "Also write narration (and scene cards if --cards) under DIR"))
              )
              ( progDesc
                  "Story Genius workflow: validate, then solve (see docs/story-genius-workflow.md). Short names use domains/NAME.ipocl and domains/NAME-problem.ipocl (e.g. misbelief, aladdin-inner, ticking-clock)."
              )
          )
    )
  where
    builtinHelp = "One of: " <> T.unpack (T.intercalate ", " (map fst builtins))

storyGeniusPaths :: FilePath -> Maybe FilePath -> (FilePath, FilePath)
storyGeniusPaths name Nothing =
  ("domains/" <> name <> ".ipocl", "domains/" <> name <> "-problem.ipocl")
storyGeniusPaths domain (Just problemFile) = (domain, problemFile)

isLargeDomain :: FilePath -> Bool
isLargeDomain path =
  let base = reverse . takeWhile (/= '/') $ reverse path
   in base == "aladdin.ipocl"

main :: IO ()
main = do
  cmd <- execParser (info (commandP <**> helper) (fullDesc <> progDesc "IPOCL narrative planner"))
  case cmd of
    Builtin name opts -> case lookup name builtins of
      Nothing -> die' ("unknown built-in problem " <> name)
      Just p -> run p opts Nothing
    SolveFiles domainFile problemFile opts ->
      loadProblem domainFile problemFile >>= either die' (\p -> run p opts Nothing)
    StoryGenius name mProblem opts mOutDir -> do
      let (domainFile, problemFile) = storyGeniusPaths name mProblem
          opts' = opts {optTimeout = optTimeout opts <|> Just 300}
      when (isLargeDomain domainFile) $
        TIO.hPutStrLn stderr "hint: for large domains such as aladdin.ipocl, try --weight 1 if search is slow"
      loadProblem domainFile problemFile >>= either die' (\p -> run p opts' mOutDir)

run :: Problem -> SolveOpts -> Maybe FilePath -> IO ()
run p opts mOutDir = do
  let issues = checkProblem p
  unless (null issues) $ do
    mapM_ (TIO.hPutStrLn stderr) issues
    exitFailure
  mapM_ (TIO.hPutStrLn stderr . ("warning: " <>)) (problemWarnings p)
  let cfg =
        defaultSolveConfig
          { cfgMaxExpanded = optMaxNodes opts <|> cfgMaxExpanded defaultSolveConfig
          , cfgTimeout = optTimeout opts
          , cfgCount = optCount opts
          , cfgHeuristic = optHeuristic opts
          , cfgWeight = optWeight opts
          , cfgGreedy = optGreedy opts
          , cfgSeed = optSeed opts
          , cfgDedupe = optDedupe opts
          }
  r <- case optTrace opts of
    Nothing -> solve cfg p
    Just file -> withFile file WriteMode $ \h -> solve cfg {cfgTrace = Just (TIO.hPutStr h . formatEvent)} p
  forM_ (zip [1 :: Int ..] (resultStories r)) $ \(i, plan) -> do
    TIO.putStrLn ("Story " <> T.pack (show i))
    mapM_ (TIO.hPutStrLn stderr . (("warning: Story " <> T.pack (show i) <> ": ") <>)) (planWarnings p plan)
    TIO.putStr (renderPlan plan)
    when (optNarrate opts) $ do
      TIO.putStrLn "Narration:"
      let narration = narrate p plan
      TIO.putStr (T.unlines (map ("  " <>) (T.lines narration)))
      forM_ mOutDir $ \dir -> do
        createDirectoryIfMissing True dir
        TIO.writeFile (dir </> ("story-" ++ show i ++ "-narration.txt")) narration
    when (optCards opts) $ do
      TIO.putStrLn "Scene cards:"
      let cards = renderCards p plan
      TIO.putStr (T.unlines (map ("  " <>) (T.lines cards)))
      forM_ mOutDir $ \dir -> do
        createDirectoryIfMissing True dir
        TIO.writeFile (dir </> ("story-" ++ show i ++ "-cards.txt")) cards
    forM_ (optDot opts) $ \file -> TIO.writeFile (dotFileFor file i) (planToDot p plan)
    let problems = validatePlan p plan
    unless (null problems) $ do
      TIO.putStrLn "INVALID:"
      mapM_ (TIO.putStrLn . ("  " <>)) problems
  TIO.putStrLn
    ( T.pack (show (resultEnd r))
        <> ": expanded "
        <> T.pack (show (resultExpanded r))
        <> ", generated "
        <> T.pack (show (resultGenerated r))
    )
  when (null (resultStories r)) exitFailure

-- | @out.dot@ for Story 1, then @out-2.dot@, @out-3.dot@, ...
dotFileFor :: FilePath -> Int -> FilePath
dotFileFor file 1 = file
dotFileFor file i = case break (== '.') (reverse name) of
  (ext, '.' : stem) | not (null stem) -> dir <> reverse stem <> suffix <> "." <> reverse ext
  _ -> file <> suffix
  where
    (dir, name) = let (n, d) = break (== '/') (reverse file) in (reverse d, reverse n)
    suffix = "-" <> show i

die' :: Text -> IO a
die' msg = TIO.hPutStrLn stderr msg >> exitFailure
