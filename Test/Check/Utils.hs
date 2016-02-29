-- | Utilities functions for manipulating tiers (sized lists of lists)
module Test.Check.Utils
  (
  -- * Additional constructors
    consFromList
  , consFromStrictlyAscendingList
  , consFromSet
  , consFromNoDupList

  -- * Products
  , tProduct3With
  , tProductMaybeWith

  -- * Tiers of lists
  , tListsOf
  , tStrictlyAscendingListsOf
  , tSetsOf
  , tNoDupListsOf
  , tProducts
  , tListsOfLength 

  -- * Choices
  , tChoices
  , tStrictlyAscendingChoices

  -- * Functions

  -- ** Listing
  , tAssociations
  , tFunctionPairs

  -- ** Pairs to actual functions
  , pairsToMaybeFunction
  , pairsToFunction
  , defaultPairsToFunction
  , defaultFunPairsToFunction
  )
where

import Test.Check.Basic
import Data.Maybe (fromMaybe, catMaybes)

-- | Given a constructor for a type that takes a list,
--   return tiers for that type.
consFromList :: Listable a => ([a] -> b) -> [[b]]
consFromList = (`tmap` tListsOf tiers)

-- | Given a constructor for a type that takes a list with strictly ascending
--   elements, return tiers of that type (e.g.: a Set type).
consFromStrictlyAscendingList :: Listable a => ([a] -> b) -> [[b]]
consFromStrictlyAscendingList = (`tmap` tStrictlyAscendingListsOf tiers)

-- | Given a constructor for a type that takes a set of elements (as a list)
--   return tiers of that type (e.g.: a Set type).
consFromSet :: Listable a => ([a] -> b) -> [[b]]
consFromSet = consFromStrictlyAscendingList

-- | Given a constructor for a type that takes a list with no duplicate
--   elements, return tiers of that type.
consFromNoDupList :: Listable a => ([a] -> b) -> [[b]]
consFromNoDupList f = tmap f (tNoDupListsOf tiers)


-- | Like 'tsProduct', but over 3 lists of tiers.
tProduct3With :: (a->b->c->d) -> [[a]] -> [[b]] -> [[c]] -> [[d]]
tProduct3With f xss yss zss = tProductWith ($) (tProductWith f xss yss) zss

-- | Take the product of lists of tiers by a function returning a maybe value.
tProductMaybeWith :: (a->b->Maybe c) -> [[a]] -> [[b]] -> [[c]]
tProductMaybeWith _ _ [] = []
tProductMaybeWith _ [] _ = []
tProductMaybeWith f (xs:xss) yss = map (productWithMaybe f xs) yss
                                \/ tProductMaybeWith f xss yss `addWeight` 1

productWithMaybe :: (a->b->Maybe c) -> [a] -> [b] -> [c]
productWithMaybe f xs ys = catMaybes $ productWith f xs ys


-- | Given tiers of values, returns tiers of lists of those values
--
-- > tListsOf [[]] == [[[]]]
--
-- > tListsOf [[x]] == [ [[]]
-- >                    , [[x]]
-- >                    , [[x,x]]
-- >                    , [[x,x,x]]
-- >                    , ...
-- >                    ]
--
-- > tListsOf [[x],[y]] == [ [[]]
-- >                        , [[x]]
-- >                        , [[x,x],[y]]
-- >                        , [[x,x,x],[x,y],[y,x]]
-- >                        , ...
-- >                        ]
tListsOf :: [[a]] -> [[[a]]]
tListsOf xss = cons0 []
            \/ tProductWith (:) xss (tListsOf xss) `addWeight` 1

-- | Generates several lists of the same size.
--
-- > tProducts [ xss, yss, zss ] ==
--
-- Tiers of all lists combining elements of tiers: xss, yss and zss 
tProducts :: [ [[a]] ] -> [[ [a] ]]
tProducts = foldr (tProductWith (:)) [[[]]]

-- | Given tiers of values, returns tiers of lists with no repeated elements.
--
-- > tNoDupListsOf [[0],[1],[2],...] ==
-- >   [ [[]]
-- >   , [[0]]
-- >   , [[1]]
-- >   , [[0,1],[1,0],[2]]
-- >   , [[0,2],[2,0],[3]]
-- >   , ...
-- >   ]
tNoDupListsOf :: [[a]] -> [[[a]]]
tNoDupListsOf = ([[]]:) . tConcat . tChoicesWith (\x xss -> tmap (x:) (tNoDupListsOf xss))

-- | Using a sized list, forms disjoint sized pairs of elements and sized lists
-- of elements.
--
-- > djs [[False,True]] == [[(False,[[True]]),(True,[[False]])]]
-- > djs [[1],[2],[3]]  == [[(1,[[],[2],[3]])],[(2,[[1],[],[3]])],[(3,[[1],[2],[]])]]
--
-- The returned list is sized by the extracted element.
-- This is intended only to be used in 'tsNoDupListsOf'
tChoices :: [[a]] -> [[(a,[[a]])]]
tChoices = tChoicesWith (,)

tChoicesWith :: (a -> [[a]] -> b) -> [[a]] -> [[b]]
tChoicesWith f []           = []
tChoicesWith f [[]]         = []
tChoicesWith f ([]:xss)     = [] : tChoicesWith (\y yss -> f y ([]:yss)) xss
tChoicesWith f ((x:xs):xss) = [[f x (xs:xss)]]
                           \/ tChoicesWith (\y (ys:yss) -> f y ((x:ys):yss)) (xs:xss)

-- | Given tiers of values,
--   returns tiers of lists of elements in crescent order
--                              (from tiered enumeration).
--   If you only care about whether elements are in returned lists,
--   this returns the tiers of all sets of values.
--
-- > tStrictlyAscendingListsOf [[0],[1],[2],...] ==
-- >   [ [[]]
-- >   , [[0]]
-- >   , [[1]]
-- >   , [[0,1],[2]]
-- >   , [[0,2],[3]]
-- >   , [[0,3],[1,2],[4]]
-- >   , [[0,1,2],[0,4],[1,3],[5]]
-- >   , ...
-- >   ]
tStrictlyAscendingListsOf :: [[a]] -> [[[a]]]
tStrictlyAscendingListsOf = ([[]]:)
                          . tConcat
                          . tStrictlyAscendingChoicesWith (\x xss -> tmap (x:) (tStrictlyAscendingListsOf xss))

-- | Returns tiers of sets represented as lists of values (no repeated sets).
--   Shorthand for 'tsStrictlyAscendingListsOf'.
tSetsOf :: [[a]] -> [[[a]]]
tSetsOf = tStrictlyAscendingListsOf

-- | Using a sized list, forms crescent sized pairs of elements and sized lists
--   of elements.  This is similar to 'djs' differing only that the elements
--   listed second in the pair are always "greater" (in terms of enumeration) than
--   the first.
--
-- tStrictlyAscendingChoices [[1],[2],[3]]  == [[(1,[[],[2],[3]])],[(2,[[],[],[3]])],[(3,[[],[],[]])]]
-- tStrictlyAscendingChoices [[False,True]] == [[(False,[[True]]),(True,[[]])]]
tStrictlyAscendingChoices :: [[a]] -> [[(a,[[a]])]]
tStrictlyAscendingChoices = tStrictlyAscendingChoicesWith (,)

tStrictlyAscendingChoicesWith :: (a -> [[a]] -> b) -> [[a]] -> [[b]]
tStrictlyAscendingChoicesWith f []           = []
tStrictlyAscendingChoicesWith f [[]]         = []
tStrictlyAscendingChoicesWith f ([]:xss)     = [] : tStrictlyAscendingChoicesWith (\y yss -> f y ([]:yss)) xss
tStrictlyAscendingChoicesWith f ((x:xs):xss) = [[f x (xs:xss)]]
                                            \/ tStrictlyAscendingChoicesWith f (xs:xss)


-- | Given tiers, returns tiers of lists of a given length.
tListsOfLength :: Int -> [[a]] -> [[[a]]]
tListsOfLength n xss = tProducts (replicate n xss)


-- | Given a list of domain values, and tiers of codomain values,
-- return tiers of lists of ordered pairs of domain and codomain values.
--
-- Technically: tiers of left-total functional relations.
tAssociations :: [a] -> [[b]] -> [[ [(a,b)] ]]
tAssociations xs sbs = zip xs `tmap` tProducts (const sbs `map` xs)

-- | Given tiers of input values and tiers of output values,
-- return tiers with all possible lists of input-output pairs.
-- Those represent functional relations.
tFunctionPairs :: [[a]] -> [[b]] -> [[[(a,b)]]]
tFunctionPairs xss yss = tConcatMap (`tAssociations` yss)
                                    (tStrictlyAscendingListsOf xss)

-- | Returns a function given by a list of input-output pairs.
-- The result is wrapped in a maybe value.
-- The output for bound inputs is 'Just' a value.
-- The output for unbound inputs is 'Nothing'.
pairsToMaybeFunction :: Eq a => [(a,b)] -> a -> Maybe b
pairsToMaybeFunction []          _ = Nothing
pairsToMaybeFunction ((a',r):bs) a | a == a'   = Just r
                                   | otherwise = pairsToMaybeFunction bs a

-- | Returns a partial function given by a list of input-output pairs.
--
-- NOTE: This function *will* return undefined values for unbound inputs.
pairsToFunction :: Eq a => [(a,b)] -> a -> b
pairsToFunction bs a = fromMaybe undefined (pairsToMaybeFunction bs a)


-- | Returns a function given by a list of input-output pairs and a default value.
defaultPairsToFunction :: Eq a => b -> [(a,b)] -> a -> b
defaultPairsToFunction r bs a = fromMaybe r (pairsToMaybeFunction bs a)


defaultFunPairsToFunction :: Eq a => (a -> b) -> [(a,b)] -> a -> b
defaultFunPairsToFunction f bs a = fromMaybe (f a) (pairsToMaybeFunction bs a)
