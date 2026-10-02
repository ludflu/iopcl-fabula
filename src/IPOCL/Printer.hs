-- | Render domains and problems in the text format read by "IPOCL.Parser".
module IPOCL.Printer
  ( printDomain
  , printProblem
  ) where

import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import IPOCL.Syntax

printDomain :: Domain -> Text
printDomain Domain {..} =
  T.unlines . closeLast $
    ("(define (domain " <> domainName <> ")")
      : predicateTexts
      ++ concatMap (("" :) . printAction) domainSchemas
  where
    predicateTexts
      | null domainPredicateTexts = []
      | otherwise = closeLast ("  (:predicate-text" : map (("    " <>) . printPredicateText) domainPredicateTexts)

printProblem :: Problem -> Text
printProblem Problem {..} =
  T.unlines . closeLast $
    [ "(define (problem " <> problemName <> ")"
    , "  (:domain " <> domainName problemDomain <> ")"
    , "  " <> sexp (":agents" : map symbolText (Set.toList problemCharacters))
    ]
      ++ closeLast ("  (:init" : map (("    " <>) . printAtom) (Set.toList problemInit))
      ++ ["  (:goal " <> printConj (map printLiteral problemOutcome) <> ")"]
      ++ requiredFrames
      ++ preferences
  where
    requiredFrames
      | null problemRequiredFrames = []
      | otherwise = closeLast ("  (:required-frames" : ["    " <> sexp [symbolText c, printLiteral g] | RequiredFrame c g <- problemRequiredFrames])
    preferences
      | null problemPreferences = []
      | otherwise = closeLast ("  (:preferences" : map (("    " <>) . printPreference) problemPreferences)

printAction :: ActionSchema -> [Text]
printAction ActionSchema {..} =
  closeLast $
    [ "  (:action " <> schemaName
    , field "parameters" (sexp (map printVar schemaParams))
    ]
      ++ [field "actors" (sexp (map printVar schemaActors)) | not (null schemaActors)]
      ++ [field "happening" "t" | schemaHappening]
      ++ [field "constraints" (printConj (map printAtom schemaConstraints)) | not (null schemaConstraints)]
      ++ [field "precondition" (printConj (map printPrecond schemaPrecondition)) | not (null schemaPrecondition)]
      ++ [field "effect" (printConj (map printLiteral schemaEffect)) | not (null schemaEffect)]
      ++ [field "text" (printString (renderTemplate t)) | Just t <- [schemaText]]
  where
    field k v = "    :" <> k <> " " <> v

printPredicateText :: PredicateText -> Text
printPredicateText PredicateText {..} =
  sexp (ptPredicate : map printVar ptParams) <> " " <> printString (renderTemplate ptTemplate)

printPreference :: Preference -> Text
printPreference (Preference rule strength) = sexp (ruleParts ++ strengthParts)
  where
    ruleParts = case rule of
      AllowGoals c ls -> "allow-goals" : symbolText c : map printLiteral ls
      ForbidGoal c l -> ["forbid-goal", symbolText c, printLiteral l]
      MaxFrames c n -> ["max-frames", symbolText c, showT n]
      NoRepeatSteps -> ["no-repeat-steps"]
    strengthParts = case strength of
      Hard -> [":hard"]
      Soft 10 -> []
      Soft w -> [":weight", showT w]

printVar :: Var -> Text
printVar v = "?" <> varName v

printTerm :: Term -> Text
printTerm = \case
  TSym s -> symbolText s
  TVar v -> printVar v
  TLit l -> printLiteral l

printAtom :: Atom -> Text
printAtom (Atom p as) = sexp (p : map printTerm as)

printLiteral :: Literal -> Text
printLiteral (Literal True a) = printAtom a
printLiteral (Literal False a) = sexp ["not", printAtom a]

printPrecond :: Precond -> Text
printPrecond = \case
  PLit l -> printLiteral l
  PNeq a b -> sexp ["neq", printTerm a, printTerm b]

printConj :: [Text] -> Text
printConj = \case
  [x] -> x
  xs -> sexp ("and" : xs)

renderTemplate :: Template -> Text
renderTemplate = T.concat . map part
  where
    part (TText t) = t
    part (TParam n) = "?" <> n

printString :: Text -> Text
printString t = "\"" <> T.concatMap escape t <> "\""
  where
    escape c
      | c `elem` ['"', '\\'] = T.pack ['\\', c]
      | otherwise = T.singleton c

sexp :: [Text] -> Text
sexp xs = "(" <> T.unwords xs <> ")"

closeLast :: [Text] -> [Text]
closeLast [] = []
closeLast xs = init xs ++ [last xs <> ")"]

showT :: Int -> Text
showT = T.pack . show
