\begin{code}
module Main where
open import Agda.Builtin.IO
open import Agda.Builtin.Unit
open import Agda.Builtin.String

postulate
  putStrLn : String → IO ⊤

{-# FOREIGN GHC import qualified Data.Text.IO as Text #-}
{-# FOREIGN GHC import qualified Data.Text as T #-}
{-# COMPILE GHC putStrLn = Text.putStrLn #-}

open import Type
open import Builtin
open import Builtin.Constant.Type
open import Builtin.Constant.Term Ctx⋆ Kind * _⊢⋆_ con
open import Builtin.Signature

open import Agda.Builtin.TrustMe
open import Relation.Binary.PropositionalEquality
open import Agda.Builtin.Nat
open import Data.Nat
open import Agda.Builtin.Int
open import Data.Integer

open import Data.Product renaming (_,_ to _,,_)
--open import test.AddInteger
--open import test.IntegerLiteral
--open import test.IntegerOverflow -- can't be used
--open import test.Negation -- TODO
--open import test.StringLiteral

open Agda.Builtin.IO
open import Data.String
postulate
  return : ∀ {a} {A : Set a} → A → IO A
  _>>=_  : ∀ {a b} {A : Set a} {B : Set b} → IO A → (A → IO B) → IO B

{-# COMPILE GHC return = \_ _ -> return    #-}
{-# COMPILE GHC _>>=_  = \_ _ _ _ -> (>>=) #-}

_>>_  : ∀ {a b} {A : Set a} {B : Set b} → IO A → IO B → IO B
x >> y = x >>= λ _ → y

open import Raw
open import Scoped
open import Utils

postulate
  imap : ∀{A B : Set} → (A → B) → IO A → IO B
  mmap : ∀{A B : Set} → (A → B) → Maybe A → Maybe B
  mbind : ∀{A B : Set} → (A → Maybe B) → Maybe A → Maybe B
  Program : Set
  convP : Program → RawTm
  readFile : String → IO ByteString
  parse : ByteString → Maybe Program
  showTerm : RawTm → String

{-# FOREIGN GHC import Language.PlutusCore.Name #-}
{-# FOREIGN GHC import Language.PlutusCore.Lexer #-}
{-# FOREIGN GHC import Language.PlutusCore.Parser #-}
{-# FOREIGN GHC import Language.PlutusCore.Pretty #-}
{-# FOREIGN GHC import Data.Either #-}

{-# FOREIGN GHC import Raw #-}
{-# COMPILE GHC convP = convP #-}
{-# FOREIGN GHC import qualified Data.ByteString.Lazy as BSL #-}
{-# COMPILE GHC imap = \_ _ -> fmap #-}
{-# COMPILE GHC mmap = \_ _ -> fmap #-}
{-# COMPILE GHC mbind = \_ _ f a -> f =<< a #-}
{-# FOREIGN GHC import Data.Either #-}
{-# COMPILE GHC parse = either (\_ -> Nothing) Just . parse #-}
{-# FOREIGN GHC import Language.PlutusCore #-}
{-# COMPILE GHC Program = type Language.PlutusCore.Program TyName Name Language.PlutusCore.Lexer.AlexPosn #-}
{-# COMPILE GHC readFile = \ s -> BSL.readFile (T.unpack s) #-}
{-# COMPILE GHC showTerm = T.pack . show #-}
open import Function

open import Untyped as U
import Untyped.Reduction as U
import Scoped as S
import Scoped.Reduction as S

open import Data.Sum

mapper : {A B : Set} → (A → B) → Maybe A → Maybe B
mapper f nothing = nothing
mapper f (just a) = just (f a)

open import Untyped

-- untyped evaluation
utestPLC : ByteString → Maybe String
utestPLC plc = mmap (U.ugly ∘ (λ (t : 0 ⊢) → proj₁ (U.run t 100)) ∘ erase⊢) (mbind (deBruijnifyTm nil) (mmap convP (parse plc)))

open import Data.Fin

postulate prettyPrint : RawTm → String

{-# COMPILE GHC prettyPrint = prettyText . unconv #-}

open import Data.Vec hiding (_>>=_)

-- extrinsically typed evaluation
stestPLC : ByteString → String
stestPLC plc with parse plc
stestPLC plc | just t with deBruijnifyTm nil (convP t)
stestPLC plc | just t | just t' with S.run (saturate t') 1000000
stestPLC plc | just t | just t' | t'' ,, p ,, inj₁ (just v) =
--  prettyPrint (unDeBruijnify zero Z (unsaturate t''))
 prettyPrint (deDeBruijnify [] nil (unsaturate t''))
stestPLC plc | just t | just t' | t'' ,, p ,, inj₁ nothing = "out of fuel"
stestPLC plc | just t | just t' | t'' ,, p ,, inj₂ e =
  "runtime error" Data.String.++
  prettyPrint (deDeBruijnify [] nil (unsaturate t''))
stestPLC plc | just t | nothing = "scope error"
stestPLC plc | nothing = "parse error"

blah : ByteString → String
blah plc with parse plc
blah plc | nothing = "parse error"
blah plc | just t with deBruijnifyTm nil (convP t)
blah plc | just t | just t' = "so far so good"
blah plc | just t | nothing = "deBruijnifying failed"

testFile : String → IO String
testFile fn = do
  t ← readFile fn
  return (stestPLC t)


{-# FOREIGN GHC import System.Environment #-}

open import Data.List

postulate getArgs : IO (List String)

{-# COMPILE GHC getArgs = (fmap . fmap) T.pack $ getArgs #-}

main : IO ⊤
main = do
  (arg ∷ args) ← getArgs
    where [] → return _
  testFile arg >>= putStrLn

ex0 : RawTm
ex0 = con (integer (pos 1))

{-
ex1 : RawTm
ex1 = (Λ "s" # (ƛ "i" (_·_ (con integer) (` "s")) (_·_ (_·_ (_·⋆_ (builtin addInteger) (` "s")) (` "i")) (_·_ (_·_ (_·⋆_ (_·⋆_ (builtin resizeInteger) (size 2)) (` "s")) (_·_ (_·⋆_ (builtin sizeOfInteger) (` "s")) (` "i"))) (con (integer 2 (pos 1)))))))
-}

open import Scoped.Reduction
frun :  ℕ → (t : ScopedTm Z)
    → Σ (ScopedTm Z) λ t' → t —→⋆ t' × (Maybe (Value t') ⊎ Error t')
frun n t = run t n
\end{code}

deBruijnifyTm nil ex1

just
(Λ "s" #
 (ƛ "i" (con integer · ` zero)
  (((builtin addInteger [] [] ·⋆ ` zero) · ` Z) ·
   ((((builtin resizeInteger [] [] ·⋆ size 2) ·⋆ ` zero) ·
     ((builtin sizeOfInteger [] [] ·⋆ ` zero) · ` Z))
    · con (integer 2 (pos 1) tt)))))

mapper saturate (deBruijnifyTm nil ex1)

just
(Λ "s" #
 (ƛ "i" (con integer · ` zero)
  (builtin addInteger (` zero ∷ [])
   (` Z ∷
    builtin resizeInteger (size 2 ∷ ` zero ∷ [])
    (builtin sizeOfInteger (` zero ∷ []) (` Z ∷ []) ∷
     con (integer 2 (pos 1) tt) ∷ [])
    ∷ []))))

unsaturate

Λ "s" #
(ƛ "i" (con integer · ` zero)
 (builtin addInteger (` zero ∷ [])
  (` Z ∷
   builtin resizeInteger (size 2 ∷ ` zero ∷ [])
   (builtin sizeOfInteger (` zero ∷ []) (` Z ∷ []) ∷
    con (integer 2 (pos 1) tt) ∷ [])
   ∷ [])))
