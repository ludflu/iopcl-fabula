-- | Strict partial orders over plan Steps, kept transitively closed.
module IPOCL.Order
  ( Order
  , emptyOrder
  , boundedOrder
  , addOrder
  , before
  , possiblyBefore
  , successors
  , orderPairs
  ) where

import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IM
import Data.IntSet (IntSet)
import Data.IntSet qualified as IS

-- | The transitive closure, as each element's successors. Optional bounds are
-- implicitly before and after every other element and are never stored.
data Order = Order
  { oAfter :: !(IntMap IntSet)
  , oLow :: !(Maybe Int)
  , oHigh :: !(Maybe Int)
  }
  deriving (Eq, Show)

emptyOrder :: Order
emptyOrder = Order IM.empty Nothing Nothing

-- | An order in which @lo@ precedes and @hi@ follows every other element.
boundedOrder :: Int -> Int -> Order
boundedOrder lo hi = Order IM.empty (Just lo) (Just hi)

-- | Stored successors; bounds are not included.
successors :: Order -> Int -> IntSet
successors o a = IM.findWithDefault IS.empty a (oAfter o)

predecessors :: Order -> Int -> IntSet
predecessors o a = IS.fromList [k | (k, s) <- IM.toList (oAfter o), IS.member a s]

before :: Order -> Int -> Int -> Bool
before o a b
  | a == b = False
  | Just a == oLow o || Just b == oHigh o = True
  | Just a == oHigh o || Just b == oLow o = False
  | otherwise = IS.member b (successors o a)

-- | @a@ could still be placed before @b@.
possiblyBefore :: Order -> Int -> Int -> Bool
possiblyBefore o a b = a /= b && not (before o b a)

-- | Add @a < b@; 'Nothing' if that would create a cycle.
addOrder :: Int -> Int -> Order -> Maybe Order
addOrder a b o
  | a == b || before o b a = Nothing
  | before o a b = Just o
  | otherwise =
      let lows = IS.insert a (predecessors o a)
          highs = IS.insert b (successors o b)
       in Just o {oAfter = IS.foldl' (\acc k -> IM.insertWith IS.union k highs acc) (oAfter o) lows}

orderPairs :: Order -> [(Int, Int)]
orderPairs o =
  [(lo, hi) | Just lo <- [oLow o], Just hi <- [oHigh o]]
    ++ [(a, b) | (a, bs) <- IM.toList (oAfter o), b <- IS.toList bs]
