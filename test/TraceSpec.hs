module TraceSpec (spec) where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import IPOCL
import IPOCL.Domains.Bribe
import IPOCL.Domains.Tiny
import IPOCL.Refine
import IPOCL.Search
import IPOCL.Syntax (Problem)
import IPOCL.Trace
import Test.Hspec

traceOf :: Int -> Problem -> T.Text
traceOf n p = T.concat (map formatEvent (take n (search (mkEnv p) defaultSearchConfig (initialPlan p))))

spec :: Spec
spec = do
  it "shows the tiny problem's path from the initial plan to the solution" $ do
    golden <- TIO.readFile "test/golden/tiny-trace.txt"
    traceOf 100 tinyProblem `shouldBe` golden
  it "gives every kind of refinement a readable reason" $ do
    let t = traceOf 2000 bribeProblem
    mapM_
      (\needle -> t `shouldSatisfy` (needle `T.isInfixOf`))
      [ "created new step"
      , "reused step"
      , "adoption of step"
      , "stays out of frame"
      , "now working on: open motivation"
      , "now working on: intent flaw for villain"
      , "solution found"
      ]
