-- | Grounding Action schemas by solving their constraints against the
-- initial state. Parameters no constraint mentions (literal-valued ones such
-- as @?objective@) stay lifted as scope-0 variables.
module IPOCL.Ground
  ( GroundAction (..)
  , groundActions
  , staticPredicates
  , instantiateTerm
  , instantiateLiteral
  , groundActionLabel
  ) where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import IPOCL.Pretty
import IPOCL.Syntax

data GroundAction = GroundAction
  { gaIndex :: !Int
  , gaSchema :: !ActionSchema
  , gaArgs :: ![Term]
  , gaActors :: ![Symbol]
  , gaHappening :: !Bool
  , gaPre :: ![Literal]
  , gaNeq :: ![(Term, Term)]
  , gaEff :: ![Literal]
  }
  deriving (Show)

instance Eq GroundAction where
  a == b = gaIndex a == gaIndex b

instance Ord GroundAction where
  compare a b = compare (gaIndex a) (gaIndex b)

-- | Predicates used in any schema's constraints; only the initial state sets them.
staticPredicates :: Domain -> Set Text
staticPredicates d = Set.fromList [atomPredicate c | s <- domainSchemas d, c <- schemaConstraints s]

groundActions :: Problem -> [GroundAction]
groundActions p =
  zipWith (\i g -> g {gaIndex = i}) [0 ..] (concatMap (groundSchema statics initIx (problemInit p)) (domainSchemas (problemDomain p)))
  where
    statics = staticPredicates (problemDomain p)
    initIx = Map.fromListWith (++) [(atomPredicate a, [a]) | a <- Set.toList (problemInit p)]

groundSchema :: Set Text -> Map Text [Atom] -> Set Atom -> ActionSchema -> [GroundAction]
groundSchema statics initIx initSet s = mapMaybe build (foldl' step [Map.empty] (schemaConstraints s))
  where
    step substs c = [s' | sub <- substs, fact <- Map.findWithDefault [] (atomPredicate c) initIx, Just s' <- [match sub (atomArgs c) (atomArgs fact)]]
    build sub = do
      let f v = maybe (TVar v) id (Map.lookup v sub)
          pres = [mapLiteralVars f l | PLit l <- schemaPrecondition s]
          neqs = [(mapTermVars f a, mapTermVars f b) | PNeq a b <- schemaPrecondition s]
      actors <- traverse (\v -> case f v of TSym sym -> Just sym; _ -> Nothing) (schemaActors s)
      mapM_ (\(a, b) -> if isGroundTerm a && a == b then Nothing else Just ()) neqs
      mapM_ staticOk pres
      Just
        GroundAction
          { gaIndex = 0
          , gaSchema = s
          , gaArgs = map (f) (schemaParams s)
          , gaActors = actors
          , gaHappening = schemaHappening s
          , gaPre = pres
          , gaNeq = [(a, b) | (a, b) <- neqs, not (isGroundTerm a && isGroundTerm b)]
          , gaEff = map (mapLiteralVars f) (schemaEffect s)
          }
    staticOk (Literal b a)
      | atomPredicate a `Set.member` statics && null (atomVars a) =
          if Set.member a initSet == b then Just () else Nothing
      | otherwise = Just ()

match :: Map Var Term -> [Term] -> [Term] -> Maybe (Map Var Term)
match sub (x : xs) (y : ys) = case x of
  TVar v -> case Map.lookup v sub of
    Nothing -> match (Map.insert v y sub) xs ys
    Just t | t == y -> match sub xs ys
    _ -> Nothing
  _ | x == y -> match sub xs ys
  _ -> Nothing
match sub [] [] = Just sub
match _ _ _ = Nothing

-- | Move a ground action's lifted variables into a Step's scope.
instantiateTerm :: Int -> Term -> Term
instantiateTerm k = mapTermVars (\(Var n _) -> TVar (Var n k))

instantiateLiteral :: Int -> Literal -> Literal
instantiateLiteral k = mapLiteralVars (\(Var n _) -> TVar (Var n k))

-- | E.g. @slay(aladdin, dragon, mountain)@.
groundActionLabel :: GroundAction -> Text
groundActionLabel g = schemaName (gaSchema g) <> "(" <> T.intercalate ", " (map prettyTerm (gaArgs g)) <> ")"
