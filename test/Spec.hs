module Main (main) where

import BindingsSpec qualified
import GroundSpec qualified
import IntentSpec qualified
import JointSpec qualified
import OrderSpec qualified
import PlannerSpec qualified
import Test.Hspec
import ValidateSpec qualified

main :: IO ()
main = hspec $ do
  describe "Order" OrderSpec.spec
  describe "Bindings" BindingsSpec.spec
  describe "Ground" GroundSpec.spec
  describe "Planner" PlannerSpec.spec
  describe "Validate" ValidateSpec.spec
  describe "Intent planning" IntentSpec.spec
  describe "Joint actions and intentional threats" JointSpec.spec
