module Main (main) where

import BindingsSpec qualified
import GroundSpec qualified
import HeuristicSpec qualified
import IntentSpec qualified
import JointSpec qualified
import NarrateSpec qualified
import RequiredSpec qualified
import TraceSpec qualified
import OrderSpec qualified
import ParserSpec qualified
import PlannerSpec qualified
import PreferenceSpec qualified
import StoriesSpec qualified
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
  describe "Trace" TraceSpec.spec
  describe "Heuristic search" HeuristicSpec.spec
  describe "Author preferences" PreferenceSpec.spec
  describe "Distinct, reproducible Stories" StoriesSpec.spec
  describe "Parser" ParserSpec.spec
  describe "Narration and DOT" NarrateSpec.spec
  RequiredSpec.spec
