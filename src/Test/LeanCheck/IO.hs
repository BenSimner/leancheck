-- |
-- Module      : Test.LeanCheck.IO
-- Copyright   : (c) 2015-2017 Rudy Matela
-- License     : 3-Clause BSD  (see the file LICENSE)
-- Maintainer  : Rudy Matela <rudy@matela.com.br>
--
-- This module is part of LeanCheck,
-- a simple enumerative property-based testing library.
--
-- QuickCheck-like interface to "Test.LeanCheck"
{-# LANGUAGE CPP #-}
module Test.LeanCheck.IO
  ( check
  , checkFor
  , checkResult
  , checkResultFor
  )
where

#if __GLASGOW_HASKELL__ <= 704
import Prelude hiding (catch)
#endif

import Test.LeanCheck.Core
import Data.Maybe (listToMaybe)
import Data.List (find)
import Control.Exception (SomeException, catch, evaluate)

-- | Checks a property printing results on 'stdout'
--
-- > > check $ \xs -> sort (sort xs) == sort (xs::[Int])
-- > +++ OK, passed 200 tests.
-- > > check $ \xs ys -> xs `union` ys == ys `union` (xs::[Int])
-- > *** Failed! Falsifiable (after 4 tests):
-- > [] [0,0]
check :: Testable a => a -> IO ()
check p = checkResult p >> return ()

-- | Check a property for a given number of tests
--   printing results on 'stdout'
checkFor :: Testable a => Int -> a -> IO ()
checkFor n p = checkResultFor n p >> return ()

-- | Check a property
--   printing results on 'stdout' and
--   returning 'True' on success.
--
-- There is no option to silence this function:
-- for silence, you should use 'Test.LeanCheck.holds'.
checkResult :: Testable a => a -> IO Bool
checkResult p = checkResultFor 200 p

-- | Check a property for a given number of tests
--   printing results on 'stdout' and
--   returning 'True' on success.
--
-- There is no option to silence this function:
-- for silence, you should use 'Test.LeanCheck.holds'.
checkResultFor :: Testable a => Int -> a -> IO Bool
checkResultFor n p = do
  r <- resultIO n p
  putStrLn . showResult n $ r
  return (isOK r)
  where isOK (OK _) = True
        isOK _      = False

data Result = OK        Int
            | Falsified Int [String]
            | Exception Int [String] String
  deriving (Eq, Show)

resultsIO :: Testable a => Int -> a -> IO [Result]
resultsIO n = sequence . zipWith torio [1..] . take n . results
  where
    tor i (_,True) = OK i
    tor i (as,False) = Falsified i as
    torio i r@(as,_) = evaluate (tor i r)
       `catch` \e -> let _ = e :: SomeException
                     in return (Exception i as (show e))

resultIO :: Testable a => Int -> a -> IO Result
resultIO n p = do
  rs <- resultsIO n p
  return . maybe (last rs) id
         $ find isFailure rs
  where isFailure (OK _) = False
        isFailure _      = True

showResult :: Int -> Result -> String
showResult m (OK n)             = "+++ OK, passed " ++ show n ++ " tests"
                               ++ takeWhile (\_ -> n < m) " (exhausted)" ++ "."
showResult m (Falsified i ce)   = "*** Failed! Falsifiable (after "
                               ++ show i ++ " tests):\n" ++ joinArgs ce
showResult m (Exception i ce e) = "*** Failed! Exception '" ++ e ++ "' (after "
                               ++ show i ++ " tests):\n" ++ joinArgs ce

-- joinArgs the counter-example arguments
joinArgs :: [String] -> String
joinArgs ce | any ('\n' `elem`) ce = unlines $ map chopBreak ce
        | otherwise            = unwords ce

-- chops a line break at the end if there is any
chopBreak :: String -> String
chopBreak [] = []
chopBreak ['\n'] = []
chopBreak (x:xs) = x:chopBreak xs
