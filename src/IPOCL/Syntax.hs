-- | Core vocabulary of IPOCL planning problems (see CONTEXT.md).
module IPOCL.Syntax
  ( -- * Terms and literals
    Symbol (..)
  , Var (..)
  , Term (..)
  , Atom (..)
  , Literal (..)
  , Precond (..)
  , pos
  , neg
  , negateLit
  , intendsPredicate
  , intendsOf
  , isIntends
    -- * Traversals
  , termVars
  , atomVars
  , literalVars
  , mapTermVars
  , mapAtomVars
  , mapLiteralVars
  , isGroundTerm
  , isGroundLiteral
    -- * Action schemas and problems
  , TemplatePart (..)
  , Template
  , ActionSchema (..)
  , PredicateText (..)
  , Domain (..)
  , Strength (..)
  , PreferenceRule (..)
  , Preference (..)
  , RequiredFrame (..)
  , Problem (..)
  , schemaByName
    -- * Embedded DSL
  , term
  , atom
  , lit
  , nlit
  , intends
  , neq
  , schema
  , template
  , problem
  ) where

import Data.List (find)
import Data.String (IsString (..))
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T

newtype Symbol = Symbol {symbolText :: Text}
  deriving (Eq, Ord, Show)

instance IsString Symbol where
  fromString = Symbol . T.pack

-- | A variable. Scope 0 is the schema's own scope; plan Steps rename their
-- variables into the scope of their StepId so Steps never share variables.
data Var = Var {varName :: !Text, varScope :: !Int}
  deriving (Eq, Ord, Show)

-- | 'TLit' lets a literal be an argument, as in @intends(?c, ¬alive(?m))@.
data Term = TSym !Symbol | TVar !Var | TLit !Literal
  deriving (Eq, Ord, Show)

data Atom = Atom {atomPredicate :: !Text, atomArgs :: ![Term]}
  deriving (Eq, Ord, Show)

data Literal = Literal {litPositive :: !Bool, litAtom :: !Atom}
  deriving (Eq, Ord, Show)

data Precond = PLit !Literal | PNeq !Term !Term
  deriving (Eq, Ord, Show)

pos, neg :: Atom -> Literal
pos = Literal True
neg = Literal False

negateLit :: Literal -> Literal
negateLit (Literal b a) = Literal (not b) a

intendsPredicate :: Text
intendsPredicate = "intends"

-- | Recognise a positive Intention @intends(character, literal-or-variable)@.
intendsOf :: Literal -> Maybe (Term, Term)
intendsOf (Literal True (Atom p [c, g])) | p == intendsPredicate = Just (c, g)
intendsOf _ = Nothing

isIntends :: Literal -> Bool
isIntends l = atomPredicate (litAtom l) == intendsPredicate

termVars :: Term -> [Var]
termVars = \case
  TSym _ -> []
  TVar v -> [v]
  TLit l -> literalVars l

atomVars :: Atom -> [Var]
atomVars = concatMap termVars . atomArgs

literalVars :: Literal -> [Var]
literalVars = atomVars . litAtom

mapTermVars :: (Var -> Term) -> Term -> Term
mapTermVars f = \case
  t@(TSym _) -> t
  TVar v -> f v
  TLit l -> TLit (mapLiteralVars f l)

mapAtomVars :: (Var -> Term) -> Atom -> Atom
mapAtomVars f (Atom p as) = Atom p (map (mapTermVars f) as)

mapLiteralVars :: (Var -> Term) -> Literal -> Literal
mapLiteralVars f (Literal b a) = Literal b (mapAtomVars f a)

isGroundTerm :: Term -> Bool
isGroundTerm = null . termVars

isGroundLiteral :: Literal -> Bool
isGroundLiteral = null . literalVars

data TemplatePart = TText !Text | TParam !Text
  deriving (Eq, Ord, Show)

-- | Narration text such as @"?slayer slays ?monster."@, split into parts.
type Template = [TemplatePart]

data ActionSchema = ActionSchema
  { schemaName :: !Text
  , schemaParams :: ![Var]
  , schemaActors :: ![Var]
  , schemaHappening :: !Bool
  , schemaConstraints :: ![Atom]
  , schemaPrecondition :: ![Precond]
  , schemaEffect :: ![Literal]
  , schemaText :: !(Maybe Template)
  }
  deriving (Eq, Show)

-- | Narration for a predicate, e.g. @(loves ?a ?b) "?a loves ?b"@.
data PredicateText = PredicateText
  { ptPredicate :: !Text
  , ptParams :: ![Var]
  , ptTemplate :: !Template
  }
  deriving (Eq, Show)

data Domain = Domain
  { domainName :: !Text
  , domainSchemas :: ![ActionSchema]
  , domainPredicateTexts :: ![PredicateText]
  }
  deriving (Eq, Show)

data Strength = Hard | Soft !Int
  deriving (Eq, Show)

data PreferenceRule
  = AllowGoals !Symbol ![Literal]
  | ForbidGoal !Symbol !Literal
  | MaxFrames !Symbol !Int
  | NoRepeatSteps
  deriving (Eq, Show)

data Preference = Preference {prefRule :: !PreferenceRule, prefStrength :: !Strength}
  deriving (Eq, Show)

-- | A Frame every Story must contain (ADR-0004).
data RequiredFrame = RequiredFrame {rfCharacter :: !Symbol, rfGoal :: !Literal}
  deriving (Eq, Show)

data Problem = Problem
  { problemName :: !Text
  , problemDomain :: !Domain
  , problemCharacters :: !(Set Symbol)
  , problemInit :: !(Set Atom)
  , problemOutcome :: ![Literal]
  , problemPreferences :: ![Preference]
  , problemRequiredFrames :: ![RequiredFrame]
  }
  deriving (Eq, Show)

schemaByName :: Domain -> Text -> Maybe ActionSchema
schemaByName d n = find ((== n) . schemaName) (domainSchemas d)

-- Embedded DSL ------------------------------------------------------------

-- | @"?x"@ is a variable, anything else a symbol.
term :: Text -> Term
term t = case T.uncons t of
  Just ('?', n) -> TVar (Var n 0)
  _ -> TSym (Symbol t)

atom :: Text -> [Text] -> Atom
atom p = Atom p . map term

lit, nlit :: Text -> [Text] -> Literal
lit p = pos . atom p
nlit p = neg . atom p

-- | @intends "?c" (Right someLiteral)@ or @intends "?c" (Left "?objective")@.
intends :: Text -> Either Text Literal -> Literal
intends c g = pos (Atom intendsPredicate [term c, either term TLit g])

neq :: Text -> Text -> Precond
neq a b = PNeq (term a) (term b)

-- | A non-happening schema with no actors, constraints, conditions or text.
schema :: Text -> [Text] -> ActionSchema
schema n ps =
  ActionSchema
    { schemaName = n
    , schemaParams = [v | p <- ps, TVar v <- [term p]]
    , schemaActors = []
    , schemaHappening = False
    , schemaConstraints = []
    , schemaPrecondition = []
    , schemaEffect = []
    , schemaText = Nothing
    }

-- | Split @"?slayer slays ?monster."@ into text and parameter parts.
template :: Text -> Template
template = go
  where
    go t
      | T.null t = []
      | otherwise = case T.breakOn "?" t of
          (before, rest)
            | T.null rest -> [TText before]
            | otherwise ->
                let (name, after) = T.span isNameChar (T.drop 1 rest)
                    here = if T.null name then [TText "?"] else [TParam name]
                 in [TText before | not (T.null before)] ++ here ++ go after
    isNameChar c = c == '-' || c == '_' || c `elem` ['a' .. 'z'] || c `elem` ['A' .. 'Z'] || c `elem` ['0' .. '9']

problem :: Text -> Domain -> [Text] -> [Atom] -> [Literal] -> Problem
problem n d cs i g =
  Problem
    { problemName = n
    , problemDomain = d
    , problemCharacters = Set.fromList (map Symbol cs)
    , problemInit = Set.fromList i
    , problemOutcome = g
    , problemPreferences = []
    , problemRequiredFrames = []
    }
