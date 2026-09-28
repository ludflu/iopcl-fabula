-- | Strict partial orders over plan Steps, kept transitively closed.
module IPOCL.Order
  ( Order
  , emptyOrder
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

-- | Transitive closure in both directions.
data Order = Order
  { oAfter :: !(IntMap IntSet)
  , oBefore :: !(IntMap IntSet)
  }
  deriving (Eq, Show)

emptyOrder :: Order
emptyOrder = Order IM.empty IM.empty

successors :: Order -> Int -> IntSet
successors o a = IM.findWithDefault IS.empty a (oAfter o)

predecessors :: Order -> Int -> IntSet
predecessors o a = IM.findWithDefault IS.empty a (oBefore o)

before :: Order -> Int -> Int -> Bool
before o a b = IS.member b (successors o a)

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
          grow m keys new = IS.foldl' (\acc k -> IM.insertWith IS.union k new acc) m keys
       in Just
            Order
              { oAfter = grow (oAfter o) lows highs
              , oBefore = grow (oBefore o) highs lows
              }

orderPairs :: Order -> [(Int, Int)]
orderPairs o = [(a, b) | (a, bs) <- IM.toList (oAfter o), b <- IS.toList bs]
