module TickingSpec (spec) where

import Data.List (elemIndex)
import Data.Text qualified as T
import Helpers
import IPOCL
import IPOCL.Parser
import IPOCL.Syntax
import Test.Hspec

-- | Ticket 20 spike: the ticks are pulled in only because the Protagonist's
-- response depends on them causally.
spec :: Spec
spec = describe "ticking-clock prototype" $
  it "has two ticks before the Protagonist defeats the consequence" $ do
    p <-
      loadProblem "domains/ticking-clock.ipocl" "domains/ticking-clock-problem.ipocl"
        >>= either (\e -> expectationFailure (T.unpack e) >> error "unreachable") pure
    s <- firstStory IPOCL p
    s `shouldBeValidFor` (IPOCL, p)
    let labels = storyLabels s
    labels `shouldBe` ["storm()", "river-rises(ruby, millbrook)", "sandbag(ruby, millbrook)"]
    elemIndex "flood(millbrook)" labels `shouldBe` Nothing
    problemProtagonist p `shouldBe` Just "ruby"
