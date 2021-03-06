{-# OPTIONS_GHC -fno-warn-incomplete-uni-patterns #-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies      #-}

module Language.PlutusCore.Examples.Data.TreeForest
    ( treeData
    , forestData
    , treeNode
    , forestNil
    , forestCons
    ) where

import           Language.PlutusCore.MkPlc
import           Language.PlutusCore.Name
import           Language.PlutusCore.Normalize
import           Language.PlutusCore.Quote
import           Language.PlutusCore.Type

import           Language.PlutusCore.StdLib.Type

{- Note [Tree]
Here we encode the following:

    mutual
      data Tree (A : Set) : Set where
        node : A -> Forest A -> Tree A

      data Forest (A : Set) : Set where
        nil  : Forest A
        cons : Tree A -> Forest A -> Forest A

    mutual
      mapTree : ∀ A B -> (A -> B) -> Tree A -> Tree B
      mapTree A B f (node x forest) = node (f x) (mapForest A B f forest)

      mapForest : ∀ A B -> (A -> B) -> Forest A -> Forest B
      mapForest A B f  nil               = nil
      mapForest A B f (cons rose forest) = cons (mapTree A B f rose) (mapForest A B f forest)

using this representation:

    {-# OPTIONS --type-in-type #-}

    {-# NO_POSITIVITY_CHECK #-}
    data IFix {A : Set} (F : (A -> Set) -> A -> Set) (x : A) : Set where
      wrap : F (IFix F) x -> IFix F x

    Fix₂ : ∀ {A B} -> ((A -> B -> Set) -> A -> B -> Set) -> A -> B -> Set
    Fix₂ F x y = IFix (λ B P -> P (F λ x y -> B λ R -> R x y)) (λ R -> R x y)

    treeTag : Set -> Set -> Set
    treeTag T F = T

    forestTag : Set -> Set -> Set
    forestTag T F = F

    AsTree : (Set -> (Set -> Set -> Set) -> Set) -> Set -> Set
    AsTree D A = D A treeTag

    AsForest : (Set -> (Set -> Set -> Set) -> Set) -> Set -> Set
    AsForest D A = D A forestTag

    TreeForest : Set -> (Set -> Set -> Set) -> Set
    TreeForest =
      Fix₂ λ Rec A tag ->
        ∀ R -> tag ((A -> AsForest Rec A -> R) -> R) (R -> (AsTree Rec A -> AsForest Rec A -> R) -> R)

    Tree : Set -> Set
    Tree = AsTree TreeForest

    Forest : Set -> Set
    Forest = AsForest TreeForest
-}

{- Note [Renaming]
We do renaming in this module, because we normalize things and this requires renaming.
-}

infixr 5 ~~>

class HasArrow a where
    (~~>) :: a -> a -> a

instance a ~ () => HasArrow (Kind a) where
    (~~>) = KindArrow ()

instance a ~ () => HasArrow (Type tyname a) where
    (~~>) = TyFun ()

star :: Kind ()
star = Type ()

treeTag :: Type TyName ()
treeTag = runQuote $ do
    t <- freshTyName () "t"
    f <- freshTyName () "f"
    return
        . TyLam () t star
        . TyLam () f star
        $ TyVar () t

forestTag :: Type TyName ()
forestTag = runQuote $ do
    t <- freshTyName () "t"
    f <- freshTyName () "f"
    return
        . TyLam () t star
        . TyLam () f star
        $ TyVar () f

asTree :: Type TyName ()
asTree = runQuote $ do
    d <- freshTyName () "d"
    a <- freshTyName () "a"
    return
        . TyLam () d (star ~~> (star ~~> star ~~> star) ~~> star)
        . TyLam () a star
        $ mkIterTyApp () (TyVar () d)
            [ TyVar () a
            , treeTag
            ]

asForest :: Type TyName ()
asForest = runQuote $ do
    d <- freshTyName () "d"
    a <- freshTyName () "a"
    return
        . TyLam () d (star ~~> (star ~~> star ~~> star) ~~> star)
        . TyLam () a star
        $ mkIterTyApp () (TyVar () d)
            [ TyVar () a
            , forestTag
            ]

treeForestData :: RecursiveType ()
treeForestData = runQuote $ do
    treeForest <- freshTyName () "treeForest"
    a          <- freshTyName () "a"
    r          <- freshTyName () "r"
    tag        <- freshTyName () "tag"
    let vA = TyVar () a
        vR = TyVar () r
        recSpine = [TyVar () treeForest, vA]
    let tree   = mkIterTyApp () asTree   recSpine
        forest = mkIterTyApp () asForest recSpine
        body
            = TyForall () r (Type ())
            $ mkIterTyApp () (TyVar () tag)
                [ (vA ~~> forest ~~> vR) ~~> vR
                , vR ~~> (tree ~~> forest ~~> vR) ~~> vR
                ]
    makeRecursiveType () treeForest
        [TyVarDecl () a star, TyVarDecl () tag $ star ~~> star ~~> star]
        body

treeData :: RecursiveType ()
treeData = runQuote $ do
    let RecursiveType treeForest wrapTreeForest = treeForestData
        tree = TyApp () asTree treeForest
    return $ RecursiveType tree (\[a] -> wrapTreeForest [a, treeTag])

forestData :: RecursiveType ()
forestData = runQuote $ do
    let RecursiveType treeForest wrapTreeForest = treeForestData
        forest = TyApp () asForest treeForest
    return $ RecursiveType forest (\[a] -> wrapTreeForest [a, forestTag])

-- See Note [Renaming].
-- |
--
-- > /\(a :: *) -> \(x : a) (fr : forest a) ->
-- >     wrapTree [a] /\(r :: *) -> \(f : a -> forest a -> r) -> f x fr
treeNode :: Term TyName Name ()
treeNode = runQuote $ normalizeTypesFullIn =<< do
    let RecursiveType _      wrapTree = treeData
        RecursiveType forest _        = forestData
    a  <- freshTyName () "a"
    r  <- freshTyName () "r"
    x  <- freshName () "x"
    fr <- freshName () "fr"
    f  <- freshName () "f"
    let vA = TyVar () a
        vR = TyVar () r
    Normalized forestA <- normalizeTypeFull $ TyApp () forest vA
    return
        . TyAbs () a (Type ())
        . LamAbs () x vA
        . LamAbs () fr forestA
        . wrapTree [vA]
        . TyAbs () r (Type ())
        . LamAbs () f (mkIterTyFun () [vA, forestA] vR)
        $ mkIterApp () (Var () f)
            [ Var () x
            , Var () fr
            ]

-- See Note [Renaming].
-- |
--
-- > /\(a :: *) ->
-- >     wrapForest [a] /\(r :: *) -> \(z : r) (f : tree a -> forest a -> r) -> z
forestNil :: Term TyName Name ()
forestNil = runQuote $ normalizeTypesFullIn =<< do
    let RecursiveType tree   _          = treeData
        RecursiveType forest wrapForest = forestData
    a <- freshTyName () "a"
    r <- freshTyName () "r"
    z <- freshName () "z"
    f <- freshName () "f"
    let vA = TyVar () a
        vR = TyVar () r
    Normalized treeA   <- normalizeTypeFull $ TyApp () tree   vA
    Normalized forestA <- normalizeTypeFull $ TyApp () forest vA
    return
        . TyAbs () a (Type ())
        . wrapForest [vA]
        . TyAbs () r (Type ())
        . LamAbs () z vR
        . LamAbs () f (mkIterTyFun () [treeA, forestA] vR)
        $ Var () z

-- See Note [Renaming].
-- |
--
-- > /\(a :: *) -> \(tr : tree a) (fr : forest a)
-- >     wrapForest [a] /\(r :: *) -> \(z : r) (f : tree a -> forest a -> r) -> f tr fr
forestCons :: Term TyName Name ()
forestCons = runQuote $ normalizeTypesFullIn =<< do
    let RecursiveType tree   _          = treeData
        RecursiveType forest wrapForest = forestData
    a  <- freshTyName () "a"
    tr <- freshName () "tr"
    fr <- freshName () "fr"
    r  <- freshTyName () "r"
    z  <- freshName () "z"
    f  <- freshName () "f"
    let vA = TyVar () a
        vR = TyVar () r
    Normalized treeA   <- normalizeTypeFull $ TyApp () tree   vA
    Normalized forestA <- normalizeTypeFull $ TyApp () forest vA
    return
        . TyAbs () a (Type ())
        . LamAbs () tr treeA
        . LamAbs () fr forestA
        . wrapForest [vA]
        . TyAbs () r (Type ())
        . LamAbs () z vR
        . LamAbs () f (mkIterTyFun () [treeA, forestA] vR)
        $ mkIterApp () (Var () f)
            [ Var () tr
            , Var () fr
            ]
