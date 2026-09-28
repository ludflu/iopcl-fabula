-- | Canonical signatures: one for search states, used to drop the same plan
-- reached by different refinement orders, and a coarser one for Stories.
module IPOCL.Signature
  ( PlanSignature
  , planSignature
  , StorySignature
  , storySignature
  , dedupeBy
  , mix64
  ) where

import Data.Bits (shiftR, xor)
import Data.Char (ord)
import Data.IntMap.Strict qualified as IM
import Data.IntSet qualified as IS
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word64)
import IPOCL.Bindings
import IPOCL.Plan
import IPOCL.Pretty
import IPOCL.Syntax

type Name = Text

type FrameKey = (Name, Text, Name, Name, [Name])

-- | A 128-bit digest of the canonical plan description. Keeping digests
-- rather than descriptions keeps the seen set small; a collision, which would
-- drop an unseen plan, is vanishingly unlikely at search scale.
data PlanSignature = PlanSignature !Word64 !Word64
  deriving (Eq, Ord, Show)

-- | Everything that determines a plan's future refinements, with Step and
-- Frame ids replaced by what they denote. A Step whose label is shared with
-- another Step keeps its id, so distinct plans never share a signature.
-- Orderings are not listed: every ordering follows from a causal link, a
-- threat ordering, Frame membership or a Frame ordering, which are.
planSignature :: Plan -> PlanSignature
planSignature plan = PlanSignature (digest 0xcbf29ce484222325 description) (digest 0x9e3779b97f4a7c15 description)
  where
    description = planDescription plan

planDescription ::
  Plan ->
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
planDescription plan =
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

-- | Seeded FNV-1a over the structure, finalised with 'mix64'.
class Digest a where
  digest :: Word64 -> a -> Word64

instance Digest Text where
  digest = T.foldl' (\h c -> (h `xor` fromIntegral (ord c)) * 0x100000001b3)

instance (Digest a) => Digest [a] where
  digest h xs = mix64 (foldl' (\acc x -> digest (acc * 31 + 0x1f) x) h xs `xor` fromIntegral (length xs))

instance (Digest a, Digest b) => Digest (a, b) where
  digest h (a, b) = digest (mix64 (digest h a)) b

instance (Digest a, Digest b, Digest c) => Digest (a, b, c) where
  digest h (a, b, c) = digest h (a, (b, c))

instance (Digest a, Digest b, Digest c, Digest d, Digest e) => Digest (a, b, c, d, e) where
  digest h (a, b, c, d, e) = digest h (a, (b, (c, (d, e))))

instance (Digest a, Digest b, Digest c, Digest d, Digest e, Digest f, Digest g, Digest i, Digest j) => Digest (a, b, c, d, e, f, g, i, j) where
  digest h (a, b, c, d, e, f, g, i, j) = digest h (a, (b, (c, (d, (e, (f, (g, (i, j))))))))

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

-- | SplitMix64 finaliser, used for seeded tie-breaking.
mix64 :: Word64 -> Word64
mix64 z0 =
  let z1 = (z0 `xor` (z0 `shiftR` 30)) * 0xbf58476d1ce4e5b9
      z2 = (z1 `xor` (z1 `shiftR` 27)) * 0x94d049bb133111eb
   in z2 `xor` (z2 `shiftR` 31)
