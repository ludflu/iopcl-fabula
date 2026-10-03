-- One-off comparison: first Aladdin Story with sequential vs parallel child builds.
module Main (main) where

import Control.Monad (forM_, when)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import GHC.Clock (getMonotonicTime)
import IPOCL
import IPOCL.Domains.Aladdin
import System.Environment (getArgs)
import System.Exit (exitFailure)

budget :: Double
budget = 300

run :: Int -> IO (Double, Int, Int, SearchEnd)
run parallelMin = do
  t0 <- getMonotonicTime
  r <-
    solve
      defaultSolveConfig
        { cfgTimeout = Just budget
        , cfgMaxExpanded = Nothing
        , cfgParallelMin = parallelMin
        }
      aladdinProblem
  t1 <- getMonotonicTime
  pure (t1 - t0, resultExpanded r, resultGenerated r, resultEnd r)

main :: IO ()
main = do
  args <- getArgs
  let caps = case args of
        ("-N" : n : _) -> read n
        _ -> 1
  forM_ [(999, "sequential children (parallelMin=999)"), (4, "parallel children (parallelMin=4, default)"), (0, "parallel off (parallelMin=0)")] $ \(minPar, label) -> do
    (t, expanded, generated, end) <- run minPar
    let t10 = fromIntegral (round (t * 10) :: Int) / 10 :: Double
    TIO.putStrLn $
      label
        <> ": "
        <> T.pack (show end)
        <> " in "
        <> T.pack (show t10)
        <> " s, expanded "
        <> T.pack (show expanded)
        <> ", generated "
        <> T.pack (show generated)
  (tSeq, _, _, endSeq) <- run 999
  (tPar, _, _, endPar) <- run 4
  when (endSeq /= Solved || endPar /= Solved) $ TIO.putStrLn "FAIL: no Story" >> exitFailure
  let gain = (tSeq - tPar) / tSeq * 100
      t10s = fromIntegral (round tSeq * 10) / 10
      t10p = fromIntegral (round tPar * 10) / 10
  TIO.putStrLn $
    "Gain (parallelMin=4 vs 999) at N"
      <> T.pack (show caps)
      <> ": "
      <> T.pack (show (fromIntegral (round (gain * 10)) / 10 :: Double))
      <> "% ("
      <> T.pack (show t10s)
      <> " s -> "
      <> T.pack (show t10p)
      <> " s)"
