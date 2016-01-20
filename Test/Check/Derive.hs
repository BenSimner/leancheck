{-# LANGUAGE TemplateHaskell, CPP #-}
-- Experimental module for deriving Listable instances
--
-- Needs GHC and Template Haskell (tested on GHC 7.4, 7.6, 7.8 and 7.10)
module Test.Check.Derive
  ( deriveListable
  , module Test.Check
  )
where

import Language.Haskell.TH
import Test.Check
import Control.Monad (when, liftM2)

#if __GLASGOW_HASKELL__ < 706
-- reportWarning was only introduced in GHC 7.6 / TH 2.8
reportWarning :: String -> Q ()
reportWarning = report False
#endif

-- | Derives a Listable instance for a given type ('Name').
deriveListable :: Name -> DecsQ
deriveListable t = do
  is <- t `isInstanceOf` ''Listable
  if is
    then do reportWarning $ "Instance Listable "
                         ++ show t
                         ++ " already exists, skipping derivation"
            return []
    else do cd <- canDeriveListable t
            when (not cd) (fail $ "Unable to derive Listable "
                               ++ show t)
            reallyDeriveListable t

-- | Checks whether it is possible to derive a Listable instance.
--
-- For example, it is not possible if there are is no Listable instance for a
-- type in one of the constructors.
canDeriveListable :: Name -> Q Bool
canDeriveListable t = return True -- TODO: Fix this, check type-cons instances

-- TODO: Somehow check if the enumeration has repetitions, then warn the user.
#if __GLASGOW_HASKELL__ >= 708
reallyDeriveListable :: Name -> DecsQ
reallyDeriveListable t = do
  (nt,vs) <- normalizeType t
#if __GLASGOW_HASKELL__ >= 710
  let cxt = sequence $ [[t| Listable $(return v) |] | v <- vs]
#else
  let cxt = sequence $ [classP ''Listable [return v] | v <- vs]
#endif
  [d| instance Listable $(return nt)
        where listing = $(conse =<< typeCons t) |]
    `appendInstancesCxtQ` cxt
  where cone n arity = do
          (Just consN) <- lookupValueName $ "cons" ++ show arity
          [| $(varE consN) $(conE n) |]
        conse = foldr1 (\e1 e2 -> [| $e1 \++/ $e2 |]) . map (uncurry cone)
#else
reallyDeriveListable :: Name -> DecsQ
reallyDeriveListable t = do
  (nt,vs) <- normalizeType t
  cxt <- sequence $ [classP ''Listable [return v] | v <- vs]
  listingE <- conse =<< typeCons t
  return [ InstanceD
             cxt
             (AppT (ConT ''Listable) nt)
             [ValD (VarP 'listing) (NormalB listingE) []]
         ]
  where cone n arity = do
          (Just consN) <- lookupValueName $ "cons" ++ show arity
          [| $(varE consN) $(conE n) |]
        conse = foldr1 (\e1 e2 -> [| $e1 \++/ $e2 |]) . map (uncurry cone)
#endif


-- * Template haskell utilities

-- Normalizes a type by applying it to necessary type variables, making it
-- accept "zero" parameters.  The normalized type is tupled with a list of
-- necessary type variables.
--
-- Suppose:
--
-- > data DT a b c ... = ...
--
-- Then, in pseudo-TH:
--
-- > normalizeType [t|DT|] == Q (DT a b c ..., [a, b, c, ...])
normalizeType :: Name -> Q (Type, [Type])
normalizeType t = do
  ar <- typeArity t
  vs <- newVarTs ar
  return (foldl AppT (ConT t) vs, vs)
  where
    newNames :: [String] -> Q [Name]
    newNames ss = mapM newName ss
    newVarTs :: Int -> Q [Type]
    newVarTs n = newNames (take n . map (:[]) . cycle $ ['a'..'z'])
             >>= return . map VarT

-- Normalizes a type by applying it to units (`()`) while possible.
--
-- > normalizeTypeUnits ''Int    === [t| Int |]
-- > normalizeTypeUnits ''Maybe  === [t| Maybe () |]
-- > normalizeTypeUnits ''Either === [t| Either () () |]
normalizeTypeUnits :: Name -> Q Type
normalizeTypeUnits t = do
  ar <- typeArity t
  return (foldl AppT (ConT t) (replicate ar (TupleT 0)))

-- Given a type name and a class name,
-- returns whether the type is an instance of that class.
isInstanceOf :: Name -> Name -> Q Bool
isInstanceOf tn cl = do
  ty <- normalizeTypeUnits tn
  isInstance cl [ty]

-- | Given a type name, return the number of arguments taken by that type.
-- Examples in partially broken TH:
--
-- > arity ''Int        === Q 0
-- > arity ''Int->Int   === Q 0
-- > arity ''Maybe      === Q 1
-- > arity ''Either     === Q 2
-- > arity ''Int->      === Q 1
--
-- This works for Data's and Newtype's and it is useful when generating
-- typeclass instances.
typeArity :: Name -> Q Int
typeArity t = do
  ti <- reify t
  return . length $ case ti of
    TyConI (DataD    _ _ ks _ _) -> ks
    TyConI (NewtypeD _ _ ks _ _) -> ks
    _                            -> error $ "error (arity): symbol "
                                         ++ show t
                                         ++ " is not a newtype or data"

-- Given a type name, returns a list of its type constructor names tupled with
-- the number of arguments they take.
typeCons :: Name -> Q [(Name,Int)]
typeCons t = do
  ti <- reify t
  return . map simplify $ case ti of
    TyConI (DataD    _ _ _ cs _) -> cs
    TyConI (NewtypeD _ _ _ c  _) -> [c]
    _ -> error $ "error (typeConstructors): symbol "
              ++ show t
              ++ " is neither newtype nor data"
  where simplify (NormalC n ts)  = (n,length ts)
        simplify (RecC    n ts)  = (n,length ts)
        simplify (InfixC  _ n _) = (n,2)

-- Append to instance contexts in a declaration.
--
-- > [t| instance Eq a => TyCl (Ty a) where foo = goo |]
-- >   `appendInstancesCxtQ` sequence [[| Eq b |], [| Eq c |]]
-- > == [t| instance (Eq a, Eq b, Eq c) => TyCl (Ty a) where foo = goo |]
appendInstancesCxtQ :: DecsQ -> Q Cxt -> DecsQ
appendInstancesCxtQ = liftM2 $ \ds c -> map (`ac` c) ds
  where ac (InstanceD c ts ds) c' = InstanceD (c++c') ts ds
        ac d                   _  = d
