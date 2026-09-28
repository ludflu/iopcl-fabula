module Main (main) where

import BindingsSpec qualified
import GroundSpec qualified
import OrderSpec qualified
import ParserSpec qualified
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
  describe "Parser" ParserSpec.spec
