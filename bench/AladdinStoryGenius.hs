-- | Level B Story Genius acceptance: full Appendix A.1 cast with protagonist
-- arc (misbelief, desire, Realization). Paper Figure 15 stays on @cabal bench aladdin@.
module Main (main) where

import Control.Monad (unless)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as T
import GHC.Clock (getMonotonicTime)
import IPOCL
import IPOCL.Narrate
import IPOCL.Parser
import IPOCL.Syntax
import IPOCL.Validate
import System.Exit (exitFailure)

budget :: Double
budget = 300

load :: IO Problem
load =
  loadProblem "domains/aladdin-story-genius.ipocl" "domains/aladdin-story-genius-problem.ipocl"
    >>= either (\e -> T.putStrLn e >> exitFailure) pure

main :: IO ()
main = do
  p <- load
  start <- getMonotonicTime
  r <- solve defaultSolveConfig {cfgTimeout = Just budget, cfgMaxExpanded = Nothing} p
  done <- getMonotonicTime
  let stories = resultStories r
      problems =
        [ "no Story within the budget" | null stories ]
          ++ [ "search took longer than 5 minutes" | done - start > budget ]
          ++ [ "Story: " <> e | s <- take 1 stories, e <- validatePlan p s ]
          ++ narrationProblems p (take 1 stories)
  report r (done - start)
  case stories of
    s : _ -> T.putStrLn (narrate p s)
    [] -> pure ()
  unless (null problems) $ mapM_ (T.putStrLn . ("FAIL: " <>)) problems >> exitFailure
  T.putStrLn "Level B Story Genius: PASS"
  where
    report r t =
      T.putStrLn $
        "first Story: "
          <> tshow (resultEnd r)
          <> " in "
          <> T.pack (show (fromIntegral (round (t * 10) :: Int) / 10 :: Double))
          <> " s, expanded "
          <> tshow (resultExpanded r)
          <> ", generated "
          <> tshow (resultGenerated r)

    narrationProblems prob ss =
      [ "narration missing misbelief or desire opening"
      | s <- ss
      , let lines' = T.lines (narrate prob s)
      , not (any ("aladdin believes" `T.isPrefixOf`) lines' && any ("aladdin wants" `T.isPrefixOf`) lines')
      ]
        ++ [ "narration missing a Realization"
           | s <- ss
           , not (any ("aladdin realizes" `T.isPrefixOf`) (T.lines (narrate prob s)))
           ]

    tshow :: (Show a) => a -> Text
    tshow = T.pack . show
