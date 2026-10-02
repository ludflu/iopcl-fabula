-- | The s-expression text format for domains and problems (spec §4.15).
module IPOCL.Parser
  ( parseDomain
  , parseProblem
  , checkedProblem
  , loadProblem
  ) where

import Control.Exception (IOException)
import Control.Exception qualified as E
import Control.Monad (void, when)
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.List (find)
import Data.Either (lefts)
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Void (Void)
import IPOCL.DomainCheck (checkProblem)
import IPOCL.Syntax
import Text.Megaparsec
import Text.Megaparsec.Char
import Text.Megaparsec.Char.Lexer qualified as L

type P = Parsec Void Text

parseDomain :: FilePath -> Text -> Either Text Domain
parseDomain path = fmap fst . runP domainFile path

parseProblem :: Domain -> FilePath -> Text -> Either Text Problem
parseProblem d path = fmap fst . runP (problemFile d) path

-- | Parse a domain and a problem given as text, then run 'checkProblem'.
-- Each issue is prefixed with the location of the action or preference it
-- concerns.
checkedProblem :: FilePath -> Text -> FilePath -> Text -> Either Text Problem
checkedProblem dPath dText pPath pText = do
  (d, actionPos) <- runP domainFile dPath dText
  (p, prefPos) <- runP (problemFile d) pPath pText
  let schemaIssues = map (locateAction dPath actionPos) (checkProblem p {problemPreferences = []})
      prefIssues =
        [ located sp issue
        | (pr, sp) <- zip (problemPreferences p) prefPos
        , issue <- checkProblem p {problemDomain = d {domainSchemas = []}, problemPreferences = [pr], problemRequiredFrames = [], problemProtagonist = Nothing, problemDesire = Nothing, problemMisbeliefs = [], problemBackstory = []}
        ]
  case schemaIssues ++ prefIssues of
    [] -> Right p
    issues -> Left (T.intercalate "\n" issues)

loadProblem :: FilePath -> FilePath -> IO (Either Text Problem)
loadProblem dPath pPath = do
  texts <- E.try ((,) <$> TIO.readFile dPath <*> TIO.readFile pPath)
  pure $ case texts of
    Left (e :: IOException) -> Left (T.pack (show e))
    Right (dText, pText) -> checkedProblem dPath dText pPath pText

runP :: P a -> FilePath -> Text -> Either Text a
runP p path src = either (Left . T.pack . errorBundlePretty) Right (parse p path src)

located :: SourcePos -> Text -> Text
located sp msg = T.pack (sourcePosPretty sp) <> ": " <> msg

locateAction :: FilePath -> [(Text, SourcePos)] -> Text -> Text
locateAction path actionPos issue =
  case find (\(n, _) -> ("action " <> n <> ": ") `T.isPrefixOf` issue) actionPos of
    Just (_, sp) -> located sp issue
    Nothing -> T.pack path <> ": " <> issue

-- Lexing ------------------------------------------------------------------

sc :: P ()
sc = L.space space1 (L.skipLineComment ";") empty

lexeme :: P a -> P a
lexeme = L.lexeme sc

parens :: P a -> P a
parens = between (lexeme (char '(')) (lexeme (char ')'))

isNameChar :: Char -> Bool
isNameChar c = isAsciiLower c || isAsciiUpper c || isDigit c || c == '-' || c == '_'

name :: P Text
name = lexeme (takeWhile1P (Just "name") isNameChar)

keyword :: Text -> P ()
keyword k = lexeme (void (try (string k <* notFollowedBy (satisfy isNameChar)))) <?> T.unpack k

variable :: P Var
variable = lexeme (char '?' *> (flip Var 0 <$> takeWhile1P (Just "variable name") isNameChar)) <?> "variable"

integer :: P Int
integer = lexeme (L.signed (pure ()) L.decimal <* notFollowedBy (satisfy isNameChar)) <?> "integer"

stringLit :: P Text
stringLit = lexeme (char '"' *> (T.pack <$> manyTill strChar (char '"'))) <?> "string"
  where
    strChar = (char '\\' *> (char '"' <|> char '\\')) <|> anySingle

failAt :: Int -> Text -> P a
failAt o msg = parseError (FancyError o (Set.singleton (ErrorFail (T.unpack msg))))

-- | Reject a repeated key, pointing at its second occurrence.
uniqueKeys :: [(Int, Text)] -> P ()
uniqueKeys = go []
  where
    go _ [] = pure ()
    go seen ((o, k) : rest)
      | k `elem` seen = failAt o ("duplicate :" <> k)
      | otherwise = go (k : seen) rest

keyed :: Text -> P a -> P (Int, Text, a)
keyed k p = do
  o <- getOffset
  keyword (":" <> k)
  (o,k,) <$> p

-- Terms and literals ------------------------------------------------------

termP :: P Term
termP = TVar <$> variable <|> TLit <$> parens literalBody <|> TSym . Symbol <$> name

predicateName :: P Text
predicateName = do
  o <- getOffset
  n <- name
  case n of
    "neq" -> failAt o "neq is only allowed in a precondition"
    _ | n `elem` ["and", "not"] -> failAt o (n <> " is not allowed here")
    _ -> pure n

atomBody :: P Atom
atomBody = Atom <$> predicateName <*> many termP

literalBody :: P Literal
literalBody = (keyword "not" *> (neg <$> parens atomBody)) <|> (pos <$> atomBody)

literalP :: P Literal
literalP = parens literalBody

precondBody :: P Precond
precondBody = (keyword "neq" *> (PNeq <$> termP <*> termP)) <|> (PLit <$> literalBody)

-- | @(and x ...)@, a single @x@, or @()@ for none. The argument parses the
-- inside of one parenthesised item.
conj :: P a -> P [a]
conj body = parens ((keyword "and" *> many (parens body)) <|> (pure <$> body) <|> pure [])

-- Domains -----------------------------------------------------------------

data Field
  = FParams [Var]
  | FActors [Var]
  | FHappening Bool
  | FConstraints [Atom]
  | FPre [Precond]
  | FEff [Literal]
  | FText Template
  | FAttemptText Template

domainFile :: P (Domain, [(Text, SourcePos)])
domainFile = between sc eof . parens $ do
  keyword "define"
  n <- parens (keyword "domain" *> name)
  sections <- many (parens (Left <$> predicateTexts <|> Right <$> action))
  pure
    ( Domain
        { domainName = n
        , domainSchemas = [fst a | Right a <- sections]
        , domainPredicateTexts = concat (lefts sections)
        }
    , [(schemaName s, sp) | Right (s, sp) <- sections]
    )

predicateTexts :: P [PredicateText]
predicateTexts = keyword ":predicate-text" *> many entry
  where
    entry = do
      (p, vs) <- parens ((,) <$> name <*> many variable)
      PredicateText p vs . template <$> stringLit

action :: P (ActionSchema, SourcePos)
action = do
  keyword ":action"
  o <- getOffset
  sp <- getSourcePos
  n <- name
  fields <-
    many $
      choice
        [ keyed "parameters" (FParams <$> parens (many variable))
        , keyed "actors" (FActors <$> parens (many variable))
        , keyed "happening" (FHappening <$> (True <$ keyword "t" <|> False <$ keyword "nil"))
        , keyed "constraints" (FConstraints <$> conj atomBody)
        , keyed "precondition" (FPre <$> conj precondBody)
        , keyed "effect" (FEff <$> conj literalBody)
        , keyed "text" (FText . template <$> stringLit)
        , keyed "attempt-text" (FAttemptText . template <$> stringLit)
        ]
  uniqueKeys [(fo, k) | (fo, k, _) <- fields]
  when (null [() | (_, _, FParams _) <- fields]) $ failAt o ("action " <> n <> " has no :parameters")
  let setField s = \case
        FParams vs -> s {schemaParams = vs}
        FActors vs -> s {schemaActors = vs}
        FHappening b -> s {schemaHappening = b}
        FConstraints as -> s {schemaConstraints = as}
        FPre ps -> s {schemaPrecondition = ps}
        FEff es -> s {schemaEffect = es}
        FText t -> s {schemaText = Just t}
        FAttemptText t -> s {schemaAttemptText = Just t}
  pure (foldl' setField (schema n []) [f | (_, _, f) <- fields], sp)

-- Problems ----------------------------------------------------------------

data Section
  = SAgents [Symbol]
  | SInit [Atom]
  | SGoal [Literal]
  | SPrefs [(Preference, SourcePos)]
  | SRequired [RequiredFrame]
  | SProtagonist Symbol
  | SDesire Literal
  | SMisbeliefs [Atom]
  | SBackstory [Atom]
  | SBackstoryCost BackstoryCost

problemFile :: Domain -> P (Problem, [SourcePos])
problemFile d = between sc eof . parens $ do
  keyword "define"
  n <- parens (keyword "problem" *> name)
  o <- getOffset
  dn <- parens (keyword ":domain" *> name)
  when (dn /= domainName d) $
    failAt o ("problem is for domain " <> dn <> " but the domain file defines " <> domainName d)
  sections <-
    many . parens $
      choice
        [ keyed "agents" (SAgents <$> many (Symbol <$> name))
        , keyed "init" (SInit <$> many (parens atomBody))
        , keyed "goal" (SGoal <$> conj literalBody)
        , keyed "preferences" (SPrefs <$> many (flip (,) <$> getSourcePos <*> parens preferenceBody))
        , keyed "required-frames" (SRequired <$> many (parens (RequiredFrame . Symbol <$> name <*> literalP <*> (True <$ keyword ":fail-first" <|> pure False))))
        , keyed "protagonist" (SProtagonist . Symbol <$> name)
        , keyed "desire" (SDesire <$> literalP)
        , keyed "misbeliefs" (SMisbeliefs <$> many (parens atomBody))
        , keyed "possible-backstory" (SBackstory <$> many (parens atomBody))
        , keyed "backstory-cost" (SBackstoryCost <$> (BackstoryCost <$> (keyword ":fact" *> integer) <*> (keyword ":intention" *> integer)))
        ]
  uniqueKeys [(so, k) | (so, k, _) <- sections]
  let prefs = concat [ps | (_, _, SPrefs ps) <- sections]
  pure
    ( Problem
        { problemName = n
        , problemDomain = d
        , problemCharacters = Set.fromList (concat [cs | (_, _, SAgents cs) <- sections])
        , problemInit = Set.fromList (concat [as | (_, _, SInit as) <- sections])
        , problemOutcome = concat [gs | (_, _, SGoal gs) <- sections]
        , problemPreferences = map fst prefs
        , problemRequiredFrames = concat [rs | (_, _, SRequired rs) <- sections]
        , problemProtagonist = listToMaybe [c | (_, _, SProtagonist c) <- sections]
        , problemDesire = listToMaybe [g | (_, _, SDesire g) <- sections]
        , problemMisbeliefs = concat [ms | (_, _, SMisbeliefs ms) <- sections]
        , problemBackstory = concat [as | (_, _, SBackstory as) <- sections]
        , problemBackstoryCost = fromMaybe defaultBackstoryCost (listToMaybe [c | (_, _, SBackstoryCost c) <- sections])
        }
    , map snd prefs
    )

preferenceBody :: P Preference
preferenceBody = Preference <$> rule <*> strength
  where
    character = Symbol <$> name
    rule =
      choice
        [ keyword "allow-goals" *> (AllowGoals <$> character <*> many literalP)
        , keyword "forbid-goal" *> (ForbidGoal <$> character <*> literalP)
        , keyword "max-frames" *> (MaxFrames <$> character <*> integer)
        , NoRepeatSteps <$ keyword "no-repeat-steps"
        , ThirdRail <$ keyword "third-rail"
        , keyword "serves-protagonist" *> (ServesProtagonist <$> character)
        , keyword "max-backstory" *> (MaxBackstory <$> integer)
        , MisbeliefBlocks <$ keyword "misbelief-blocks"
        ]
    strength =
      (Hard <$ keyword ":hard")
        <|> (Soft <$> (keyword ":weight" *> integer))
        <|> pure (Soft 10)
