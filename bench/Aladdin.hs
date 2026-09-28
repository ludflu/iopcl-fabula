-- | Acceptance Level B: the full Aladdin problem of Appendix A.1, with the
-- paper's preferences, solved in under five minutes.
module Main (main) where

import Control.Monad (forM_, unless)
import Data.IntMap.Strict qualified as IM
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as T
import GHC.Clock (getMonotonicTime)
import IPOCL
import IPOCL.Domains.Aladdin
import IPOCL.Pretty
import IPOCL.Report
import IPOCL.Syntax
import IPOCL.Validate
import System.Exit (exitFailure)

-- | (Character, Character goal) pairs of Figure 15.
figure15 :: Set (Text, Text)
figure15 =
  Set.fromList
    [ ("jafar", "married-to(jafar, jasmine)")
    , ("aladdin", "has(jafar, lamp)")
    , ("aladdin", "¬alive(genie)")
    , ("genie", "loves(jasmine, jafar)")
    , ("jasmine", "married-to(jasmine, jafar)")
    ]

frameSet :: Plan -> Set (Text, Text)
frameSet plan = Set.fromList [(symbolText (frameCharacter f), prettyLiteral (resolvedGoal plan f)) | f <- IM.elems (planFrames plan)]

budget :: Double
budget = 300

main :: IO ()
main = do
  start <- getMonotonicTime
  first <- solve defaultSolveConfig {cfgTimeout = Just budget, cfgMaxExpanded = Nothing} aladdinProblem
  firstDone <- getMonotonicTime
  report "first Story" first (firstDone - start)
  more <- solve defaultSolveConfig {cfgTimeout = Just budget, cfgMaxExpanded = Nothing, cfgCount = 5} aladdinProblem
  moreDone <- getMonotonicTime
  report "first five Stories" more (moreDone - firstDone)
  let stories = resultStories more
      problems =
        [ "no Story within the budget" | null (resultStories first) ]
          ++ [ "first Story took longer than 5 minutes" | firstDone - start > budget ]
          ++ [ "Story " <> tshow i <> ": " <> e | (i, s) <- zip [1 :: Int ..] stories, e <- validatePlan IPOCL aladdinProblem s ]
          ++ [ "no Story among the first five has the Frames of Figure 15" | figure15 `notElem` map frameSet stories ]
  forM_ (take 1 (resultStories first)) (T.putStrLn . renderPlan)
  forM_ (zip [1 :: Int ..] stories) $ \(i, s) ->
    T.putStrLn ("Story " <> tshow i <> (if frameSet s == figure15 then ": Frames match Figure 15" else ": other Frames"))
  unless (null problems) $ mapM_ (T.putStrLn . ("FAIL: " <>)) problems >> exitFailure
  T.putStrLn "Level B: PASS"
  where
    report what r t =
      T.putStrLn $
        what
          <> ": "
          <> tshow (resultOutcome r)
          <> " in "
          <> T.pack (show (fromIntegral (round (t * 10) :: Int) / 10 :: Double))
          <> " s, expanded "
          <> tshow (resultExpanded r)
          <> ", generated "
          <> tshow (resultGenerated r)
    tshow :: (Show a) => a -> Text
    tshow = T.pack . show
