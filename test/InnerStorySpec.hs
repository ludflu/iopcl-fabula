module InnerStorySpec (spec) where

import Data.IntMap.Strict qualified as IM
import Data.List (elemIndex)
import Data.Text (Text)
import Data.Text qualified as T
import Helpers
import IPOCL
import IPOCL.DomainCheck
import IPOCL.Lint
import IPOCL.Narrate
import IPOCL.Parser
import IPOCL.Pretty
import IPOCL.Printer
import IPOCL.Syntax
import Test.Hspec

loadMisbelief :: IO Problem
loadMisbelief =
  loadProblem "domains/misbelief.ipocl" "domains/misbelief-problem.ipocl"
    >>= either (\e -> expectationFailure (T.unpack e) >> error "unreachable") pure

-- | The problem with only the named schemas left out.
without :: [Text] -> Problem -> Problem
without names p =
  let d = problemDomain p
   in p {problemDomain = d {domainSchemas = filter ((`notElem` names) . schemaName) (domainSchemas d)}}

belief :: Atom
belief = Atom believesPredicate [TSym "ruby", TLit (lit "dangerous" ["love"])]

limited :: Problem -> Result
limited = solvePure defaultSolveConfig {cfgMaxExpanded = Just 5000}

-- | The Story's labels, checking it is valid and that the Realization comes
-- before the Step it unblocks.
realizedBy :: Text -> Problem -> IO [Text]
realizedBy realization p = do
  s <- firstStory IPOCL p
  s `shouldBeValidFor` (IPOCL, p)
  let labels = storyLabels s
      at l = elemIndex l labels
  at (realization <> "(ruby, henry)") `shouldSatisfy` (< at "confess-love(ruby, henry)")
  at (realization <> "(ruby, henry)") `shouldNotBe` Nothing
  [g | (c, g, _, _) <- frameSummary s, c == "ruby"] `shouldContain` ["reunited(ruby, henry)"]
  pure labels

spec :: Spec
spec = describe "Protagonist, Desire and Misbeliefs" $ do
  describe "syntax" $
    it "round-trips the misbelief example" $ do
      p <- loadMisbelief
      problemProtagonist p `shouldBe` Just "ruby"
      problemDesire p `shouldBe` Just (lit "reunited" ["ruby", "henry"])
      problemMisbeliefs p `shouldBe` [belief]
      requiredFrames p `shouldBe` [RequiredFrame "ruby" (lit "reunited" ["ruby", "henry"]) False]
      parseProblem (problemDomain p) "p" (printProblem p) `shouldBe` Right p

  describe "domain checks" $ do
    it "accepts the example without warnings" $ do
      p <- loadMisbelief
      checkProblem p `shouldBe` []
      problemWarnings p `shouldBe` []
    it "rejects a Protagonist who is not a Character" $ do
      p <- loadMisbelief
      checkProblem p {problemProtagonist = Just "nora"} `shouldContain` ["protagonist nora is not a character"]
    it "rejects a Desire without a Protagonist" $ do
      p <- loadMisbelief
      checkProblem p {problemProtagonist = Nothing} `shouldBe` ["a desire needs a protagonist"]
    it "rejects a Desire the Protagonist does not intend initially" $ do
      p <- loadMisbelief
      checkProblem p {problemDesire = Just (lit "reunited" ["henry", "ruby"])}
        `shouldBe` ["the protagonist ruby does not intend the desire reunited(henry, ruby) in the initial state"]
    it "rejects a Misbelief that does not hold initially, or is not about a Character" $ do
      p <- loadMisbelief
      let notHeld = Atom believesPredicate [TSym "henry", TLit (lit "dangerous" ["love"])]
          noCharacter = Atom believesPredicate [TSym "love"]
          notBelief = Atom "loves" [TSym "ruby", TSym "henry"]
      checkProblem p {problemMisbeliefs = [notHeld]} `shouldBe` ["misbelief " <> prettyAtom notHeld <> " does not hold in the initial state"]
      checkProblem p {problemMisbeliefs = [noCharacter]}
        `shouldBe` [ "misbelief " <> prettyAtom noCharacter <> " does not hold in the initial state"
                   , "misbelief " <> prettyAtom noCharacter <> ": its first argument must be a character, followed by the belief"
                   ]
      checkProblem p {problemMisbeliefs = [notBelief]} `shouldBe` ["misbelief " <> prettyAtom notBelief <> " is not a believes fact"]
    it "warns when no Action can overturn a Misbelief" $ do
      p <- loadMisbelief
      problemWarnings (without ["near-loss", "rescue"] p)
        `shouldContain` ["misbelief " <> prettyAtom belief <> ": no action can overturn it"]
    it "warns when the Misbelief does not stand in the way of the Desire" $ do
      p <- loadMisbelief
      let d = problemDomain p
          unblocked s
            | schemaName s == "confess-love" = s {schemaPrecondition = take 1 (schemaPrecondition s)}
            | otherwise = s
          easy = p {problemDomain = d {domainSchemas = map unblocked (domainSchemas d)}}
      problemWarnings easy `shouldBe` ["the misbeliefs of ruby do not stand in the way of the desire reunited(ruby, henry)"]

  describe "planning" $ do
    it "puts a Realization by a Happening before the blocked Step" $ do
      labels <- loadMisbelief >>= realizedBy "near-loss" . without ["rescue"]
      labels `shouldBe` ["near-loss(ruby, henry)", "confess-love(ruby, henry)"]
    it "puts a Realization by an intentional Step before the blocked Step" $ do
      labels <- loadMisbelief >>= realizedBy "rescue" . without ["near-loss"]
      labels `shouldBe` ["rescue(ruby, henry)", "confess-love(ruby, henry)"]
    it "finds no Story without a Realization" $ do
      p <- loadMisbelief
      resultEnd (limited (without ["near-loss", "rescue"] p)) `shouldBe` Exhausted
    it "always gives the Protagonist a Frame for the Desire" $ do
      p <- loadMisbelief
      let ss = resultStories (solvePure defaultSolveConfig {cfgMaxExpanded = Just 5000, cfgCount = 5} p)
      length ss `shouldSatisfy` (> 1)
      mapM_ (\s -> any (\f -> frameCharacter f == "ruby" && resolvedGoal s f == lit "reunited" ["ruby", "henry"]) (IM.elems (planFrames s)) `shouldBe` True) ss

  describe "narration" $
    it "opens with the Misbelief and the Desire, and marks the Realization" $ do
      p <- without ["rescue"] <$> loadMisbelief
      s <- firstStory IPOCL p
      T.lines (narrate p s)
        `shouldBe` [ "ruby believes love is dangerous."
                   , "ruby wants ruby is with henry."
                   , "ruby almost loses henry."
                   , "ruby realizes it is not the case that love is dangerous."
                   , "ruby tells henry she loves him so that ruby is with henry."
                   ]
