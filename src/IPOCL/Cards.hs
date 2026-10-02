-- | Story Genius scene cards (Cron, ch. 11): one card per Step, read off the
-- plan's links and Frames.
module IPOCL.Cards
  ( LinkRef (..)
  , SceneCard (..)
  , linkSource
  , linkTarget
  , sceneCards
  , renderCards
  ) where

import Data.IntMap.Strict qualified as IM
import Data.IntSet qualified as IS
import Data.List (sortOn)
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import IPOCL.Bindings
import IPOCL.Linearize
import IPOCL.Narrate
import IPOCL.Plan
import IPOCL.Syntax

-- | A causal link, or the motivation link from a Frame's Motivating step to
-- the first Step of its Interval.
data LinkRef
  = Causal !CausalLink
  | Motivation !FrameId !StepId !StepId
  deriving (Eq, Ord, Show)

data SceneCard = SceneCard
  { cardStep :: !Step
  , cardIncoming :: ![LinkRef]
  -- ^ What happens: the links that made this Step possible.
  , cardConsequence :: ![Literal]
  -- ^ Effects that some causal or motivation link consumes.
  , cardFrames :: ![Frame]
  -- ^ Why it matters: the Frames whose Interval contains the Step.
  , cardInternal :: ![Literal]
  -- ^ Internal change: Intentions the Step gives.
  , cardOutgoing :: ![LinkRef]
  -- ^ And so?: the links leaving this Step.
  }

linkSource, linkTarget :: LinkRef -> StepId
linkSource = \case
  Causal l -> linkFrom l
  Motivation _ m _ -> m
linkTarget = \case
  Causal l -> linkTo l
  Motivation _ _ s -> s

-- | One card per Step other than init and goal, in narration order.
sceneCards :: Plan -> [SceneCard]
sceneCards plan = map card (filter isActionStep order)
  where
    b = planBindings plan
    order = linearize plan
    position sid = IM.findWithDefault maxBound sid (IM.fromList (zip (map stepId order) [0 :: Int ..]))
    frames = IM.elems (planFrames plan)
    firstMember f = case filter (`IS.member` frameInterval f) (map stepId order) of
      s : _ -> Just s
      [] -> Nothing
    refs =
      map Causal (Set.toList (planLinks plan))
        ++ [Motivation (frameId f) m s | f <- frames, Just m <- [frameMotivator f], Just s <- [firstMember f]]
    carried = \case
      Causal l -> [resolveLiteral b (linkCond l)]
      Motivation fid _ _ -> [resolveLiteral b (frameIntention f) | Just f <- [IM.lookup fid (planFrames plan)]]
    card s =
      let sid = stepId s
          out = sortOn (position . linkTarget) [r | r <- refs, linkSource r == sid]
       in SceneCard
            { cardStep = s
            , cardIncoming = sortOn (position . linkSource) [r | r <- refs, linkTarget r == sid]
            , cardConsequence = Set.toList (Set.fromList (concatMap carried out))
            , cardFrames = [f | f <- frames, IS.member sid (frameInterval f)]
            , cardInternal = [resolveLiteral b e | not (isUnexecuted plan (stepId s)), e <- stepEff s, isIntends e]
            , cardOutgoing = out
            }

-- | The cards as text, numbered in narration order.
renderCards :: Problem -> Plan -> Text
renderCards p plan = T.unlines (concat (zipWith render [1 :: Int ..] (sceneCards plan)))
  where
    d = problemDomain p
    b = planBindings plan
    stepText sid = maybe "?" (\s -> if isUnexecuted plan sid then renderAttempt d plan s else renderStep d plan s) (IM.lookup sid (planSteps plan))
    clause sid = let t = stepText sid in fromMaybe t (T.stripSuffix "." t)
    source sid = if sid == initStepId then "the initial state" else clause sid
    target sid
      | sid == goalStepId = "the Outcome"
      | Just c <- IM.lookup sid (planRequired plan) = "the Required Frame of " <> symbolText c
      | otherwise = clause sid
    literal = renderLiteral d . resolveLiteral b
    frameText fid = case IM.lookup fid (planFrames plan) of
      Just f -> symbolText (frameCharacter f) <> " wants " <> literal (frameGoal f)
      Nothing -> "?"
    incoming = \case
      Causal l -> source (linkFrom l) <> " makes it true that " <> literal (linkCond l)
      Motivation fid m _ -> source m <> " gives the reason: " <> frameText fid
    outgoing = \case
      Causal l -> literal (linkCond l) <> ", needed by " <> target (linkTo l)
      Motivation fid _ s -> frameText fid <> ", which leads to " <> target s
    internal e = case intendsOf e of
      Just (TSym ch, TLit g) -> symbolText ch <> " comes to want " <> literal g
      _ -> literal e
    render i c =
      [ "Scene " <> T.pack (show i) <> ": " <> stepText (stepId (cardStep c))
      , "  What happens:" <> list (map incoming (cardIncoming c))
      , "  The consequence:" <> if null (cardConsequence c) then " no consequence used" else list (map internal (cardConsequence c))
      ]
        ++ ["  Why it matters:" <> list (map (frameText . frameId) (cardFrames c)) | not (stepHappening (cardStep c))]
        ++ ["  Internal change:" <> list (map internal (cardInternal c)) | not (null (cardInternal c))]
        ++ ["  And so?" <> list (map outgoing (cardOutgoing c)), ""]
    list [] = " nothing"
    list xs = T.concat (map ("\n    - " <>) xs)
