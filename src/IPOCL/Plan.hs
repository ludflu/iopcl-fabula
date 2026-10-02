-- | IPOCL plans (Def. 4): Steps, bindings, orderings, causal links and Frames.
module IPOCL.Plan
  ( StepId
  , FrameId
  , initStepId
  , goalStepId
  , Step (..)
  , CausalLink (..)
  , Frame (..)
  , Plan (..)
  , Flaw (..)
  , Mode (..)
  , initialPlan
  , planStepList
  , actionSteps
  , stepLabel
  , resolvedGoal
  , frameIntention
  , framesOf
  , isMotivator
  , orphans
  ) where

import Data.IntMap.Strict (IntMap)
import Data.Ord (Down)
import Data.IntMap.Strict qualified as IM
import Data.IntSet (IntSet)
import Data.IntSet qualified as IS
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import IPOCL.Bindings
import IPOCL.Ground
import IPOCL.Order
import IPOCL.Pretty
import IPOCL.Syntax

type StepId = Int

type FrameId = Int

initStepId, goalStepId :: StepId
initStepId = 0
goalStepId = 1

data Step = Step
  { stepId :: !StepId
  , stepAction :: !(Maybe GroundAction)
  -- ^ 'Nothing' for the init and goal Steps.
  , stepArgs :: ![Term]
  , stepActors :: ![Symbol]
  , stepHappening :: !Bool
  , stepPre :: ![Literal]
  , stepEff :: ![Literal]
  }
  deriving (Show)

data CausalLink = CausalLink
  { linkFrom :: !StepId
  , linkCond :: !Literal
  , linkTo :: !StepId
  }
  deriving (Eq, Ord, Show)

data Frame = Frame
  { frameId :: !FrameId
  , frameCharacter :: !Symbol
  , frameGoal :: !Literal
  , frameFinal :: !(Maybe StepId)
  -- ^ Always 'Just' for now; 'Nothing' is reserved for failed intentions.
  , frameInterval :: !IntSet
  , frameMotivator :: !(Maybe StepId)
  }
  deriving (Eq, Show)

data Plan = Plan
  { planSteps :: !(IntMap Step)
  , planBindings :: !Bindings
  , planOrder :: !Order
  , planLinks :: !(Set CausalLink)
  , planFrames :: !(IntMap Frame)
  , planFrameOrder :: !(Set (FrameId, FrameId))
  -- ^ @(a, b)@: every Step of Frame @a@ precedes every Step of Frame @b@.
  , planOpenConds :: ![(StepId, Literal)]
  , planPendingIntent :: ![(StepId, FrameId)]
  , planProposedIntent :: !(Set (StepId, FrameId))
  , planThreatOrders :: !(Set (StepId, StepId))
  -- ^ Orderings added by promotion or demotion, kept for rendering.
  , planThreats :: !(Set (CausalLink, Down StepId))
  -- ^ Causal threats as (link, clobbering Step). The descending Step order is
  -- the order flaw selection has always seen; changing it changes the search.
  , planNextStep :: !StepId
  , planNextFrame :: !FrameId
  }
  deriving (Show)

data Flaw
  = OpenCondition !StepId !Literal
  | CausalThreat !StepId !CausalLink
  | OpenMotivation !FrameId
  | IntentFlaw !StepId !FrameId
  | IntentionalThreat !FrameId !FrameId
  deriving (Eq, Show)

data Mode = IPOCL | POCL
  deriving (Eq, Show)

initialPlan :: Problem -> Plan
initialPlan p =
  Plan
    { planSteps = IM.fromList [(initStepId, initStep), (goalStepId, goalStep)]
    , planBindings = emptyBindings
    , planOrder = boundedOrder initStepId goalStepId
    , planLinks = Set.empty
    , planFrames = IM.empty
    , planFrameOrder = Set.empty
    , planOpenConds = [(goalStepId, l) | l <- problemOutcome p]
    , planPendingIntent = []
    , planProposedIntent = Set.empty
    , planThreatOrders = Set.empty
    , planThreats = Set.empty
    , planNextStep = 2
    , planNextFrame = 0
    }
  where
    initStep = Step initStepId Nothing [] [] True [] (map pos (Set.toList (problemInit p)))
    goalStep = Step goalStepId Nothing [] [] True (problemOutcome p) []

planStepList :: Plan -> [Step]
planStepList = IM.elems . planSteps

-- | Every Step except init and goal.
actionSteps :: Plan -> [Step]
actionSteps = filter (\s -> stepId s > goalStepId) . planStepList

stepLabel :: Plan -> Step -> Text
stepLabel plan s = case stepAction s of
  Nothing
    | stepId s == initStepId -> "init"
    | otherwise -> "goal"
  Just g ->
    schemaName (gaSchema g)
      <> "("
      <> T.intercalate ", " (map (prettyTerm . resolve (planBindings plan)) (stepArgs s))
      <> ")"

resolvedGoal :: Plan -> Frame -> Literal
resolvedGoal plan = resolveLiteral (planBindings plan) . frameGoal

-- | The Intention a Frame's Motivating step must establish.
frameIntention :: Frame -> Literal
frameIntention f = pos (Atom intendsPredicate [TSym (frameCharacter f), TLit (frameGoal f)])

framesOf :: Plan -> Symbol -> [Frame]
framesOf plan c = filter ((== c) . frameCharacter) (IM.elems (planFrames plan))

-- | (Step, Actor) pairs of non-Happening Steps outside every Frame of that Actor.
orphans :: Plan -> [(StepId, Symbol)]
orphans plan =
  [ (stepId s, a)
  | s <- actionSteps plan
  , not (stepHappening s)
  , a <- stepActors s
  , not (any (IS.member (stepId s) . frameInterval) (framesOf plan a))
  ]

isMotivator :: Plan -> StepId -> Bool
isMotivator plan s = any ((== Just s) . frameMotivator) (IM.elems (planFrames plan))
