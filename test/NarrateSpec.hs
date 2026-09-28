module NarrateSpec (spec) where

import Data.Char (isAlphaNum)
import Data.IntMap.Strict qualified as IM
import Data.List (findIndex)
import Data.Maybe (mapMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Helpers
import IPOCL
import IPOCL.Domains.Bribe
import IPOCL.Dot
import IPOCL.Narrate
import IPOCL.Pretty
import IPOCL.Syntax
import Test.Hspec

withoutTemplates :: Problem -> Problem
withoutTemplates p =
  p {problemDomain = d {domainSchemas = [s {schemaText = Nothing} | s <- domainSchemas d]}}
  where
    d = problemDomain p

lineIndex :: Text -> [Text] -> Maybe Int
lineIndex needle = findIndex (== needle)

spec :: Spec
spec = do
  describe "narrate" $ do
    it "states each Character's intention before the Steps taken for it" $ do
      plan <- firstStory IPOCL bribeProblem
      let ls = T.lines (narrate bribeProblem plan)
          at n = maybe (error ("missing line: " <> T.unpack n)) id (lineIndex n ls)
      at "villain wants villain controls president." `shouldSatisfy` (< at "villain coerces hero.")
      at "hero wants villain has money." `shouldSatisfy` (< at "hero gives money to villain.")
    it "matches the Bribe golden narration" $ do
      plan <- firstStory IPOCL bribeProblem
      golden <- TIO.readFile "test/golden/bribe-narration.txt"
      narrate bribeProblem plan `shouldBe` golden
    it "falls back to \"name args\" for a Step without a template" $ do
      let p = withoutTemplates bribeProblem
      plan <- firstStory IPOCL p
      T.lines (narrate p plan) `shouldContain` ["give hero villain money"]
    it "renders a negated Character goal" $
      renderLiteral bribeDomain (nlit "has" ["hero", "money"]) `shouldBe` "it is not the case that hero has money"
    it "phrases a negated Character goal as something wanted not to be the case" $ do
      let stories = resultStories (solvePure defaultSolveConfig {cfgCount = 2, cfgMaxExpanded = Just 50000} bribeProblem)
          ls = concatMap (T.lines . narrate bribeProblem) stories
      ls `shouldContain` ["hero wants it not to be the case that hero has money."]
    it "falls back to the printed literal when a predicate has no template" $
      renderLiteral bribeDomain (lit "armed" ["hero"]) `shouldBe` prettyLiteral (lit "armed" ["hero"])

  describe "planToDot" $ do
    it "matches the Bribe golden DOT" $ do
      plan <- firstStory IPOCL bribeProblem
      golden <- TIO.readFile "test/golden/bribe.dot"
      planToDot bribeProblem plan `shouldBe` golden
    it "is a structurally valid digraph" $ do
      plan <- firstStory IPOCL bribeProblem
      let dot = planToDot bribeProblem plan
      dotProblems dot `shouldBe` []
    it "draws one labelled cluster per Frame" $ do
      plan <- firstStory IPOCL bribeProblem
      let dot = planToDot bribeProblem plan
      mapM_
        ( \f -> do
            dot `shouldSatisfy` T.isInfixOf ("subgraph cluster_" <> T.pack (show (frameId f)) <> " {")
            dot
              `shouldSatisfy` T.isInfixOf
                ("label=\"" <> symbolText (frameCharacter f) <> ": " <> prettyLiteral (resolvedGoal plan f) <> "\"")
        )
        (IM.elems (planFrames plan))
    it "draws orderings added to resolve threats dashed" $ do
      plan <- firstStory IPOCL bribeProblem
      let dot = planToDot bribeProblem plan {planThreatOrders = Set.singleton (3, 2)}
      dot `shouldSatisfy` T.isInfixOf "s3 -> s2 [style=dashed];"
      dotProblems dot `shouldBe` []
    it "draws motivation links dotted and causal links solid" $ do
      plan <- firstStory IPOCL bribeProblem
      let dot = planToDot bribeProblem plan
      dot `shouldSatisfy` T.isInfixOf "style=dotted"
      dot `shouldSatisfy` T.isInfixOf "label=\"has(villain, money)\""

-- | Lightweight structural checks standing in for @dot -Tsvg@.
dotProblems :: Text -> [String]
dotProblems dot =
  [ "missing digraph header" | not ("digraph " `T.isPrefixOf` dot)]
    ++ ["unbalanced braces" | not (balanced (T.unpack dot))]
    ++ ["undeclared edge endpoint " <> T.unpack e | e <- concatMap endpoints edges, e `notElem` declared]
  where
    ls = map T.strip (T.lines dot)
    edges = filter (T.isInfixOf " -> ") ls
    endpoints l = let (a, rest) = T.breakOn " -> " l in [a, T.takeWhile isIdent (T.drop 4 rest)]
    declared = mapMaybe nodeDecl ls
    nodeDecl l =
      let (ident, rest) = T.span isIdent l
       in if not (T.null ident) && " [" `T.isPrefixOf` rest && not (ident `elem` ["node", "edge", "graph"])
            then Just ident
            else Nothing
    isIdent c = isAlphaNum c || c == '_'

-- | Braces balance outside quoted strings.
balanced :: String -> Bool
balanced = go (0 :: Int) False
  where
    go n _ [] = n == 0
    go n True ('\\' : _ : cs) = go n True cs
    go n q ('"' : cs) = go n (not q) cs
    go n True (_ : cs) = go n True cs
    go n False ('{' : cs) = go (n + 1) False cs
    go n False ('}' : cs) = n > 0 && go (n - 1) False cs
    go n False (_ : cs) = go n False cs
