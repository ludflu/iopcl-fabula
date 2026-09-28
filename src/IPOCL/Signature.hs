-- | Canonical signatures: one for search states, used to drop the same plan
-- reached by different refinement orders, and a coarser one for Stories.
module IPOCL.Signature
  ( PlanSignature
  , planSignature
  , StorySignature
  , storySignature
  , dedupeBy
  ) where

import Data.IntMap.Strict qualified as IM
import Data.IntSet qualified as IS
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import IPOCL.Bindings
import IPOCL.Plan
import IPOCL.Pretty
import IPOCL.Syntax

type Name = Text

type FrameKey = (Name, Text, Name, Name, [Name])

newtype PlanSignature
  = PlanSignature
      ( [Name]
      , [(Name, Text, Name)]
      , [(Name, Name)]
      , [FrameKey]
      , [(FrameKey, FrameKey)]
      , [(Name, Text)]
      , [(Name, FrameKey)]
      , [(Name, FrameKey)]
      , [(Text, Text)]
      )
  deriving (Eq, Ord)

-- | Everything that determines a plan's future refinements, with Step and
-- Frame ids replaced by what they denote. A Step whose label is shared with
-- another Step keeps its id, so distinct plans never share a signature.
-- Orderings are not listed: every ordering follows from a causal link, a
-- threat ordering, Frame membership or a Frame ordering, which are.
planSignature :: Plan -> PlanSignature
planSignature plan =
  PlanSignature
    ( sort (map (stepName . stepId) steps)
    , sort [(stepName f, literal c, stepName t) | CausalLink f c t <- Set.toList (planLinks plan)]
    , sort [(stepName x, stepName y) | (x, y) <- Set.toList (planThreatOrders plan)]
    , sort (map frameKey (IM.elems (planFrames plan)))
    , sort [(frameName x, frameName y) | (x, y) <- Set.toList (planFrameOrder plan)]
    , sort [(stepName s, literal l) | (s, l) <- planOpenConds plan]
    , sort [(stepName s, frameName f) | (s, f) <- planPendingIntent plan]
    , sort [(stepName s, frameName f) | (s, f) <- Set.toList (planProposedIntent plan)]
    , sort [(prettyTerm (resolve bs x), prettyTerm (resolve bs y)) | (x, y) <- neqConstraints bs]
    )
  where
    bs = planBindings plan
    steps = planStepList plan
    literal = prettyLiteral . resolveLiteral bs
    labels = IM.fromList [(stepId s, stepLabel plan s) | s <- steps]
    counts = Map.fromListWith (+) [(l, 1 :: Int) | l <- IM.elems labels]
    stepName i = case IM.lookup i labels of
      Just l | Map.lookup l counts == Just 1 -> l
      Just l -> l <> "@" <> T.pack (show i)
      Nothing -> "@" <> T.pack (show i)
    frameKey f =
      ( symbolText (frameCharacter f)
      , literal (frameGoal f)
      , maybe "-" stepName (frameFinal f)
      , maybe "-" stepName (frameMotivator f)
      , sort (map stepName (IS.toList (frameInterval f)))
      )
    frameName i = maybe ("?", "?", "?", "?", []) frameKey (IM.lookup i (planFrames plan))

-- | Stories count as different when their ground Steps or their
-- (Character, Character goal) pairs differ.
type StorySignature = ([Text], Set (Text, Text))

storySignature :: Plan -> StorySignature
storySignature plan =
  ( sort (map (stepLabel plan) (actionSteps plan))
  , Set.fromList [(symbolText (frameCharacter f), prettyLiteral (resolvedGoal plan f)) | f <- IM.elems (planFrames plan)]
  )

-- | Keep the items whose key has not been seen, in order, and extend the seen set.
dedupeBy :: Ord k => (a -> k) -> Set k -> [a] -> ([a], Set k)
dedupeBy key seen0 = go seen0
  where
    go seen = \case
      [] -> ([], seen)
      x : xs
        | Set.member k seen -> go seen xs
        | otherwise -> let (kept, seen') = go (Set.insert k seen) xs in (x : kept, seen')
        where
          k = key x
