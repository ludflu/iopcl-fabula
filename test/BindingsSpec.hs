module BindingsSpec (spec) where

import Data.Maybe (isNothing)
import IPOCL.Bindings
import IPOCL.Syntax
import Test.Hspec

x, objective :: Term
x = TVar (Var "x" 3)
objective = TVar (Var "objective" 7)

intendsOfTerm :: Term -> Term -> Literal
intendsOfTerm c g = pos (Atom intendsPredicate [c, g])

spec :: Spec
spec = do
  it "binds a variable to a symbol" $
    fmap (`resolve` x) (unify emptyBindings x (term "genie")) `shouldBe` Just (term "genie")
  it "binds a literal-valued parameter to a whole literal" $ do
    let want = intends "aladdin" (Right (lit "has" ["jafar", "lamp"]))
        effect = intendsOfTerm (term "aladdin") objective
    fmap (`resolve` objective) (unifyLiterals emptyBindings effect want)
      `shouldBe` Just (TLit (lit "has" ["jafar", "lamp"]))
  it "unifies through nested negative literals" $ do
    let want = intends "aladdin" (Right (nlit "alive" ["genie"]))
        effect = intendsOfTerm (term "aladdin") (TLit (neg (Atom "alive" [x])))
    fmap (`resolve` x) (unifyLiterals emptyBindings effect want) `shouldBe` Just (term "genie")
  it "refuses to unify literals of different polarity inside intends" $ do
    let want = intends "aladdin" (Right (nlit "alive" ["genie"]))
        effect = intendsOfTerm (term "aladdin") (TLit (pos (Atom "alive" [x])))
    isNothing (unifyLiterals emptyBindings effect want) `shouldBe` True
  it "refuses a binding that would make a non-codesignation equal" $ do
    (addNeq emptyBindings x (term "genie") >>= \b -> unify b x (term "genie")) `shouldSatisfy` isNothing
  it "rejects cyclic bindings" $
    isNothing (unify emptyBindings x (TLit (pos (Atom "p" [x])))) `shouldBe` True
