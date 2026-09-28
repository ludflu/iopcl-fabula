module OrderSpec (spec) where

import Data.Maybe (isNothing)
import IPOCL.Order
import Test.Hspec hiding (before)
import Test.QuickCheck

-- | Apply orderings in turn, keeping the accepted ones.
applyAll :: [(Int, Int)] -> (Order, [(Int, Int)])
applyAll = foldl step (emptyOrder, [])
  where
    step (o, acc) (a, b) = case addOrder a b o of
      Just o' -> (o', (a, b) : acc)
      Nothing -> (o, acc)

smallPairs :: [(Small Int, Small Int)] -> [(Int, Int)]
smallPairs es = [(getSmall a `mod` 12, getSmall b `mod` 12) | (a, b) <- es]

spec :: Spec
spec = do
  it "is transitive" $
    fmap (\o -> before o 1 3) (addOrder 1 2 emptyOrder >>= addOrder 2 3) `shouldBe` Just True
  it "rejects an ordering that closes a cycle" $
    isNothing (addOrder 1 2 emptyOrder >>= addOrder 2 3 >>= addOrder 3 1) `shouldBe` True
  it "rejects ordering a step before itself" $
    isNothing (addOrder 4 4 emptyOrder) `shouldBe` True
  it "never becomes cyclic, whatever orderings are attempted" $
    property $ \es ->
      let (o, _) = applyAll (smallPairs es)
       in all (\(a, b) -> not (before o b a)) (orderPairs o)
  it "keeps every accepted ordering" $
    property $ \es ->
      let (o, accepted) = applyAll (smallPairs es)
       in all (\(a, b) -> before o a b) accepted
