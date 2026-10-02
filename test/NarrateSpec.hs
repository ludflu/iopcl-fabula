module NarrateSpec (spec) where

import Data.Char (isAlphaNum)
import Data.IntMap.Strict qualified as IM
import Data.List (elemIndex, sort)
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Helpers
import IPOCL
import IPOCL.Cards
import IPOCL.Domains.Bribe
import IPOCL.Dot
import IPOCL.Linearize
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
lineIndex = elemIndex

spec :: Spec
spec = do
  describe "narrate" $ do
    it "states each Character's intention before the Steps taken for it" $ do
      plan <- firstStory IPOCL bribeProblem
      let ls = T.lines (narrate bribeProblem plan)
          at n = fromMaybe (error ("missing line: " <> T.unpack n)) (lineIndex n ls)
      at "villain wants villain controls president." `shouldSatisfy` (< at "villain coerces hero so that villain controls president.")
      at "hero wants villain has money." `shouldSatisfy` (< at "hero gives money to villain so that villain has money.")
    it "matches the Bribe golden narration" $ do
      plan <- firstStory IPOCL bribeProblem
      golden <- TIO.readFile "test/golden/bribe-narration.txt"
      narrate bribeProblem plan `shouldBe` golden
    it "falls back to \"name args\" for a Step without a template" $ do
      let p = withoutTemplates bribeProblem
      plan <- firstStory IPOCL p
      T.lines (narrate p plan) `shouldContain` ["give hero villain money so that villain has money."]
    it "opens a Frame at its first Step and closes it at its final Step" $ do
      plan <- firstStory IPOCL bribeProblem
      let ls = T.lines (narrate bribeProblem plan)
      ls `shouldContain` ["villain coerces hero so that villain controls president."]
      ls `shouldContain` ["villain bribes president with money, and so villain controls president."]
    it "gives a single-Step Frame one combined clause" $ do
      plan <- firstStory IPOCL bribeProblem
      let ls = T.lines (narrate bribeProblem plan)
      filter ("hero gives" `T.isPrefixOf`) ls `shouldBe` ["hero gives money to villain so that villain has money."]
    it "renders a negated Character goal" $
      renderLiteral bribeDomain (nlit "has" ["hero", "money"]) `shouldBe` "it is not the case that hero has money"
    it "phrases a negated Character goal as something wanted not to be the case" $ do
      let stories = resultStories (solvePure defaultSolveConfig {cfgCount = 2, cfgMaxExpanded = Just 50000} bribeProblem)
          ls = concatMap (T.lines . narrate bribeProblem) stories
      ls `shouldContain` ["hero wants it not to be the case that hero has money."]
    it "falls back to the printed literal when a predicate has no template" $
      renderLiteral bribeDomain (lit "armed" ["hero"]) `shouldBe` prettyLiteral (lit "armed" ["hero"])

  describe "scene cards" $ do
    it "has one card per Step other than init and goal, in narration order" $ do
      plan <- firstStory IPOCL bribeProblem
      map (stepId . cardStep) (sceneCards plan) `shouldBe` [stepId s | s <- linearize plan, stepId s > goalStepId]
    it "shows every link between two Steps on exactly the source's and the target's cards" $ do
      plan <- firstStory IPOCL bribeProblem
      let cards = sceneCards plan
          onCards r = [(stepId (cardStep c), side) | c <- cards, (side, rs) <- [("in", cardIncoming c), ("out", cardOutgoing c)], r `elem` rs]
          refs = concatMap cardIncoming cards ++ concatMap cardOutgoing cards
          between r = linkSource r > goalStepId && linkTarget r > goalStepId
      refs `shouldSatisfy` any between
      mapM_ (\r -> sort (onCards r) `shouldBe` sort [(linkTarget r, "in" :: Text), (linkSource r, "out")]) (filter between refs)
    it "flags a Step none of whose effects is used" $ do
      plan <- firstStory IPOCL bribeProblem
      let unlinked = plan {planLinks = Set.filter ((/= goalStepId) . linkTo) (planLinks plan)}
      renderCards bribeProblem unlinked `shouldSatisfy` T.isInfixOf "The consequence: no consequence used"
    it "matches the Bribe golden cards" $ do
      plan <- firstStory IPOCL bribeProblem
      golden <- TIO.readFile "test/golden/bribe-cards.txt"
      renderCards bribeProblem plan `shouldBe` golden

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
       in if not (T.null ident) && " [" `T.isPrefixOf` rest && ident `notElem` ["node", "edge", "graph"]
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
