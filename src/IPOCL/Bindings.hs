-- | Binding constraints: variable codesignations plus non-codesignations.
module IPOCL.Bindings
  ( Bindings
  , emptyBindings
  , resolve
  , resolveAtom
  , resolveLiteral
  , unify
  , unifyAtoms
  , unifyLiterals
  , addNeq
  , neqConstraints
  , necessarilyEqual
  ) where

import Control.Monad (foldM, guard)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import IPOCL.Syntax

data Bindings = Bindings
  { bSubst :: !(Map Var Term)
  , bNeq :: ![(Term, Term)]
  }
  deriving (Eq, Show)

emptyBindings :: Bindings
emptyBindings = Bindings Map.empty []

-- | Fully dereference a term under the bindings.
resolve :: Bindings -> Term -> Term
resolve b = \case
  t@(TSym _) -> t
  TVar v -> maybe (TVar v) (resolve b) (Map.lookup v (bSubst b))
  TLit l -> TLit (resolveLiteral b l)

resolveAtom :: Bindings -> Atom -> Atom
resolveAtom b (Atom p as) = Atom p (map (resolve b) as)

resolveLiteral :: Bindings -> Literal -> Literal
resolveLiteral b (Literal s a) = Literal s (resolveAtom b a)

necessarilyEqual :: Bindings -> Term -> Term -> Bool
necessarilyEqual b x y = resolve b x == resolve b y

neqConstraints :: Bindings -> [(Term, Term)]
neqConstraints = bNeq

-- | Most general unifier extending the bindings, respecting non-codesignations.
unify :: Bindings -> Term -> Term -> Maybe Bindings
unify b0 x0 y0 = go b0 x0 y0 >>= checkNeq
  where
    go b x y = case (resolve b x, resolve b y) of
      (TVar v, TVar w) | v == w -> Just b
      (TVar v, t) -> bindVar b v t
      (t, TVar v) -> bindVar b v t
      (TSym s, TSym s') -> b <$ guard (s == s')
      (TLit l, TLit l') -> goLit b l l'
      _ -> Nothing
    goLit b (Literal s a) (Literal s' a') = guard (s == s') >> goAtom b a a'
    goAtom b (Atom p as) (Atom p' as') = do
      guard (p == p' && length as == length as')
      foldM (\acc (x, y) -> go acc x y) b (zip as as')
    bindVar b v t = do
      guard (v `notElem` termVars t)
      Just b {bSubst = Map.insert v t (bSubst b)}

unifyAtoms :: Bindings -> Atom -> Atom -> Maybe Bindings
unifyAtoms b (Atom p as) (Atom p' as') = do
  guard (p == p' && length as == length as')
  foldM (\acc (x, y) -> unify acc x y) b (zip as as')

-- | Unify two literals of the same polarity.
unifyLiterals :: Bindings -> Literal -> Literal -> Maybe Bindings
unifyLiterals b (Literal s a) (Literal s' a') = guard (s == s') >> unifyAtoms b a a'

addNeq :: Bindings -> Term -> Term -> Maybe Bindings
addNeq b x y = checkNeq b {bNeq = (x, y) : bNeq b}

checkNeq :: Bindings -> Maybe Bindings
checkNeq b = b <$ mapM_ (\(x, y) -> guard (not (necessarilyEqual b x y))) (bNeq b)
