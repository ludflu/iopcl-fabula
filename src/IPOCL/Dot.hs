-- | Graphviz rendering of a plan in the style of Fig. 15.
--
-- Steps are boxes; init and goal are grey ellipses. Causal links are solid
-- edges labelled with their conditions, orderings added to resolve threats are
-- dashed, and each Frame is a cluster labelled @character: goal@ with a dotted
-- motivation link from its Motivating step into the cluster.
module IPOCL.Dot
  ( planToDot
  ) where

import Data.IntMap.Strict qualified as IM
import Data.IntSet qualified as IS
import Data.List (find)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import IPOCL.Bindings
import IPOCL.Plan
import IPOCL.Pretty
import IPOCL.Syntax

planToDot :: Problem -> Plan -> Text
planToDot p plan =
  T.unlines $
    ["digraph " <> quote (problemName p) <> " {"]
      ++ map ("  " <>) header
      ++ concatMap cluster frames
      ++ map ("  " <>) (map nodeLine unclustered)
      ++ map ("  " <>) (causalEdges ++ threatEdges ++ motivationEdges)
      ++ ["}"]
  where
    header =
      [ "compound=true;"
      , "rankdir=TB;"
      , "node [shape=box, fontname=\"Helvetica\"];"
      , "edge [fontname=\"Helvetica\", fontsize=10];"
      ]
    frames = IM.elems (planFrames plan)
    steps = planStepList plan
    -- A node can be drawn in only one cluster: the lowest-numbered Frame
    -- whose Interval contains it.
    home sid = frameId <$> find (IS.member sid . frameInterval) frames
    unclustered = [s | s <- steps, home (stepId s) == Nothing]
    cluster f =
      ["  subgraph cluster_" <> showT (frameId f) <> " {", "    label=" <> quote (frameLabel f) <> ";", "    style=rounded;"]
        ++ ["    " <> nodeLine s | s <- steps, home (stepId s) == Just (frameId f)]
        ++ ["  }"]
    frameLabel f = symbolText (frameCharacter f) <> ": " <> prettyLiteral (resolvedGoal plan f)
    nodeLine s
      | stepId s == initStepId || stepId s == goalStepId =
          node s <> " [label=" <> quote (stepLabel plan s) <> ", shape=ellipse, style=filled, fillcolor=lightgrey];"
      | otherwise = node s <> " [label=" <> quote (stepLabel plan s <> alsoIn s) <> happening s <> "];"
    alsoIn s = case [frameId f | f <- frames, IS.member (stepId s) (frameInterval f), home (stepId s) /= Just (frameId f)] of
      [] -> ""
      fs -> "\nalso in frame " <> T.intercalate ", " (map showT fs)
    happening s = if stepHappening s then ", style=dashed" else ""
    causalEdges =
      [ nodeId a <> " -> " <> nodeId b <> " [label=" <> quote (T.intercalate "\n" conds) <> "];"
      | ((a, b), conds) <- Map.toList linkGroups
      ]
    linkGroups =
      Map.fromListWith
        (flip (++))
        [ ((linkFrom l, linkTo l), [prettyLiteral (resolveLiteral (planBindings plan) (linkCond l))])
        | l <- Set.toList (planLinks plan)
        ]
    threatEdges = [nodeId a <> " -> " <> nodeId b <> " [style=dashed];" | (a, b) <- Set.toList (planThreatOrders plan)]
    motivationEdges =
      [ nodeId m
          <> " -> "
          <> nodeId t
          <> " [label="
          <> quote (prettyLiteral (resolveLiteral (planBindings plan) (frameIntention f)))
          <> ", style=dotted, arrowhead=empty"
          <> lhead f m t
          <> "];"
      | f <- frames
      , Just m <- [frameMotivator f]
      , Just t <- [frameFinal f]
      ]
    lhead f m t
      | home t == Just (frameId f) && home m /= Just (frameId f) = ", lhead=cluster_" <> showT (frameId f)
      | otherwise = ""
    node = nodeId . stepId

nodeId :: StepId -> Text
nodeId = ("s" <>) . showT

showT :: (Show a) => a -> Text
showT = T.pack . show

quote :: Text -> Text
quote t = "\"" <> T.concatMap esc t <> "\""
  where
    esc = \case
      '"' -> "\\\""
      '\\' -> "\\\\"
      '\n' -> "\\n"
      c -> T.singleton c
