
{-# LANGUAGE BangPatterns #-}

module Main (main) where

import Data.List (foldl')
import System.CPUTime (getCPUTime)
import Text.Printf (printf)
import Control.DeepSeq (force)
import Control.Exception (evaluate)

-- Cong don bang foldl (lazy).
sumLazy :: [Int] -> Int
sumLazy = foldl (+) 0

-- Cong don bang foldl' (strict).
sumStrict :: [Int] -> Int
sumStrict = foldl' (+) 0

-- Do thoi gian CPU cho mot phep tinh.
benchmark :: String -> ([Int] -> Int) -> [Int] -> IO ()
benchmark label f values = do
  start <- getCPUTime
  !result <- evaluate (force (f values))
  end <- getCPUTime

  let elapsedMs =
        fromIntegral (end - start) / 1.0e9 :: Double

  printf "%s: result=%d, cpu=%.3f ms\n"
    label result elapsedMs

main :: IO ()
main = do
  let values = [1 .. 3000000] :: [Int]

  putStrLn "===== LAZY VS STRICT ====="
  benchmark "foldl " sumLazy values
  benchmark "foldl'" sumStrict values
