-- | Sweep weighted A* on Aladdin (Level B bench config, no expansion cap).
-- See also bench/Aladdin.hs for acceptance checks.
module Main (main) where

import Control.Monad (forM_)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as T
import GHC.Clock (getMonotonicTime)
import IPOCL
import IPOCL.Domains.Aladdin
import System.Environment (getArgs)

weights :: [Double]
weights = [1, 1.5, 2, 3, 5]

benchCfg :: Int -> SolveConfig
benchCfg seed =
  defaultSolveConfig
    { cfgMaxExpanded = Nothing
    , cfgTimeout = Just 300
    , cfgCount = 1
    , cfgSeed = seed
    }

main :: IO ()
main = do
  seed <- parseSeed <$> getArgs
  T.putStrLn "W\tSearchEnd\texpanded\tgenerated\twall_s"
  forM_ weights $ \w ->
    runRow (weightLabel w) ((benchCfg seed) {cfgWeight = w})
  runRow "greedy" ((benchCfg seed) {cfgGreedy = True})

runRow :: Text -> SolveConfig -> IO ()
runRow label cfg = do
  start <- getMonotonicTime
  r <- solve cfg aladdinProblem
  end <- getMonotonicTime
  let wall = fromIntegral (round ((end - start) * 10) :: Int) / 10 :: Double
  T.putStrLn $
    label
      <> "\t"
      <> tshow (resultEnd r)
      <> "\t"
      <> tshow (resultExpanded r)
      <> "\t"
      <> tshow (resultGenerated r)
      <> "\t"
      <> T.pack (show wall)

weightLabel :: Double -> Text
weightLabel w
  | w == fromIntegral (i :: Int) = T.pack (show i)
  | otherwise = T.pack (show w)
  where
    i = truncate w

parseSeed :: [String] -> Int
parseSeed = go
  where
    go [] = 0
    go ("--seed" : s : _) = read s
    go (_ : rest) = go rest

tshow :: (Show a) => a -> Text
tshow = T.pack . show
