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
  , isActionStep
  , stepLabel
  , resolvedGoal
  , frameIntention
  , frameEnd
  , isUnexecuted
  , framesOf
  , isMotivator
  , orphans
  ) where

import Control.Applicative ((<|>))
import Data.IntMap.Strict (IntMap)
import Data.Ord (Down)
import Data.IntMap.Strict qualified as IM
import Data.IntSet (IntSet)
import Data.IntSet qualified as IS
import Data.Maybe (fromMaybe, isJust)
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
  -- ^ 'Nothing' for the init and goal Steps and pseudo-steps.
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
  -- ^ 'Nothing' for a failed Frame (ADR-0003).
  , frameInterval :: !IntSet
  , frameMotivator :: !(Maybe StepId)
  , frameAttempt :: !(Maybe StepId)
  -- ^ The attempted Step of a failed Frame.
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
  , planRequired :: !(IntMap Symbol)
  , planBackstory :: !(Set Atom)
  , planUnexecuted :: !IntSet
  -- ^ Attempted Steps: placed and ordered, but their effects never happen.
  , planOpenAttempts :: ![StepId]
  -- ^ Pseudo-steps of ':fail-first' Required Frames still without a failed Frame.
  , planFailFirst :: !(IntMap FrameId)
  -- ^ Pseudo-step of a ':fail-first' Required Frame to its failed Frame.
  -- ^ Committed backstory, also added to the init Step's effects.
  -- ^ Pseudo-steps of Required Frames (ADR-0004), with their Character.
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
  | OpenAttempt !StepId
  -- ^ A ':fail-first' pseudo-step that still needs its failed Frame.
  deriving (Eq, Show)

data Mode = IPOCL | POCL
  deriving (Eq, Show)

initialPlan :: Problem -> Plan
initialPlan p =
  Plan
    { planSteps = IM.fromList ([(initStepId, initStep), (goalStepId, goalStep)] ++ [(stepId s, s) | s <- pseudo])
    , planBindings = emptyBindings
    , planOrder = foldl (\o s -> fromMaybe o (addOrder initStepId (stepId s) o >>= addOrder (stepId s) goalStepId)) (boundedOrder initStepId goalStepId) pseudo
    , planLinks = Set.empty
    , planFrames = IM.empty
    , planFrameOrder = Set.empty
    , planOpenConds = [(goalStepId, l) | l <- problemOutcome p] ++ [(stepId s, g) | s <- pseudo, g <- stepPre s]
    , planPendingIntent = []
    , planProposedIntent = Set.empty
    , planThreatOrders = Set.empty
    , planThreats = Set.empty
    , planBackstory = Set.empty
    , planUnexecuted = IS.empty
    , planOpenAttempts = [k | (k, r) <- required, rfFailFirst r]
    , planFailFirst = IM.empty
    , planRequired = IM.fromList [(k, rfCharacter r) | (k, r) <- required]
    , planNextStep = 2 + length required
    , planNextFrame = 0
    }
  where
    initStep = Step initStepId Nothing [] [] True [] (map pos (Set.toList (problemInit p)))
    goalStep = Step goalStepId Nothing [] [] True (problemOutcome p) []
    required = zip [2 ..] (requiredFrames p)
    pseudo = [Step k Nothing [] [] True [rfGoal r] [] | (k, r) <- required]

planStepList :: Plan -> [Step]
planStepList = IM.elems . planSteps

-- | Every Step except init, goal and pseudo-steps.
actionSteps :: Plan -> [Step]
actionSteps = filter isActionStep . planStepList

isActionStep :: Step -> Bool
isActionStep = isJust . stepAction

stepLabel :: Plan -> Step -> Text
stepLabel plan s = case stepAction s of
  Nothing
    | stepId s == initStepId -> "init"
    | stepId s == goalStepId -> "goal"
    | otherwise -> "required " <> maybe "?" symbolText (IM.lookup (stepId s) (planRequired plan)) <> " " <> T.unwords (map (prettyLiteral . resolveLiteral (planBindings plan)) (stepPre s))
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

-- | The final Step, or the attempted Step of a failed Frame: the Step every
-- other member precedes.
frameEnd :: Frame -> Maybe StepId
frameEnd f = frameFinal f <|> frameAttempt f

isUnexecuted :: Plan -> StepId -> Bool
isUnexecuted plan s = IS.member s (planUnexecuted plan)

framesOf :: Plan -> Symbol -> [Frame]
framesOf plan c = filter ((== c) . frameCharacter) (IM.elems (planFrames plan))

-- | (Step, Actor) pairs of non-Happening Steps outside every Frame of that Actor.
-- Only the failed Frame's Character needs a Frame for an attempted Step.
orphans :: Plan -> [(StepId, Symbol)]
orphans plan =
  [ (stepId s, a)
  | s <- actionSteps plan
  , not (stepHappening s)
  , a <- stepActors s
  , not (isUnexecuted plan (stepId s)) || any (\f -> frameAttempt f == Just (stepId s) && frameCharacter f == a) (IM.elems (planFrames plan))
  , not (any (IS.member (stepId s) . frameInterval) (framesOf plan a))
  ]

isMotivator :: Plan -> StepId -> Bool
isMotivator plan s = any ((== Just s) . frameMotivator) (IM.elems (planFrames plan))
