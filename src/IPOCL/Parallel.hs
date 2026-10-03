-- | Optional parallelism inside one refinement, without changing search order.
module IPOCL.Parallel
  ( parallelMap
  , defaultParallelMin
  ) where

import Control.Parallel.Strategies (parMap, rseq)
import GHC.Conc (getNumCapabilities)
import System.IO.Unsafe (unsafePerformIO)

-- | Default minimum candidate count before using 'parMap'.
defaultParallelMin :: Int
defaultParallelMin = 4

rtsCapabilities :: Int
rtsCapabilities = unsafePerformIO getNumCapabilities
{-# NOINLINE rtsCapabilities #-}

-- | Like 'map', but evaluates each result in parallel when the list is long
-- enough and the RTS has more than one capability. Order is preserved.
parallelMap :: Int -> (a -> b) -> [a] -> [b]
parallelMap minCount f xs
  | minCount > 0, length xs >= minCount, rtsCapabilities > 1 = parMap rseq f xs
  | otherwise = map f xs
