-- | Compact human-readable rendering, e.g. @¬alive(genie)@.
module IPOCL.Pretty
  ( prettyTerm
  , prettyAtom
  , prettyLiteral
  , prettyPrecond
  ) where

import Data.Text (Text)
import Data.Text qualified as T
import IPOCL.Syntax

prettyTerm :: Term -> Text
prettyTerm = \case
  TSym (Symbol s) -> s
  TVar (Var n 0) -> "?" <> n
  TVar (Var n k) -> "?" <> n <> "#" <> T.pack (show k)
  TLit l -> prettyLiteral l

prettyAtom :: Atom -> Text
prettyAtom (Atom p []) = p
prettyAtom (Atom p as) = p <> "(" <> T.intercalate ", " (map prettyTerm as) <> ")"

prettyLiteral :: Literal -> Text
prettyLiteral (Literal True a) = prettyAtom a
prettyLiteral (Literal False a) = "¬" <> prettyAtom a

prettyPrecond :: Precond -> Text
prettyPrecond = \case
  PLit l -> prettyLiteral l
  PNeq a b -> prettyTerm a <> " ≠ " <> prettyTerm b
