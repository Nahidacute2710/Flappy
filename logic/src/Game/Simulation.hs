{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
module Simulation
  ( SimulationResult(..)
  , runParallel
  , runSequential
  , BossSimResult(..)
  , runBossParallel
  , runBossSequential
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (ToJSON)
import Control.Parallel.Strategies (parMap, rdeepseq)
import Data.List (foldl')
import GHC.Generics (Generic)
import GameState
import GameLoop (initialGameState, stepGame, newBoss)

data SimulationResult = SimulationResult
  { scenarioId :: Int
  , framesSimulated :: Int
  , finalScore :: Int
  , endedByCollision :: Bool
  } deriving (Show, Eq, Generic, NFData)

instance ToJSON SimulationResult

-- Each scenario starts from the real game state but varies pipe animation phase
-- deterministically, so the scenarios are independent and can be evaluated in parallel.
runScenario :: Int -> Int -> SimulationResult
runScenario scenario frames =
  let base = initialGameState
      offset = fromIntegral (scenario `mod` 17) * 0.19
      variedPipes = zipWith (\i p -> p { pipePhase = pipePhase p + offset + fromIntegral i * 0.07 }) [0 :: Int ..] (gamePipes base)
      start = base { gamePipes = variedPipes, gameStatus = Playing }
      final = foldl' (\st _ -> stepGame NoInput st) start [1 .. max 0 frames]
  in SimulationResult
       { scenarioId = scenario
       , framesSimulated = max 0 frames
       , finalScore = gameScore final
       , endedByCollision = gameStatus final == GameOver
       }

runSequential :: Int -> Int -> [SimulationResult]
runSequential count frames = map (\i -> runScenario i frames) [1 .. max 0 count]

runParallel :: Int -> Int -> [SimulationResult]
runParallel count frames = parMap rdeepseq (\i -> runScenario i frames) [1 .. max 0 count]

data BossSimResult = BossSimResult
  { bossScenarioId :: Int
  , bossRoundNo    :: Int
  , bossSurvived   :: Bool
  , bossFramesUsed :: Int
  } deriving (Show, Eq, Generic, NFData)

instance ToJSON BossSimResult

-- Mỗi kịch bản bắt đầu thẳng trong màn boss, chim do bot lái.
runBossScenario :: Int -> Int -> BossSimResult
runBossScenario roundNo scenario =
  let score = roundNo * 10
      boss0 = newBoss roundNo
      boss1 = boss0 { bossFireCooldown = 0.5 + fromIntegral (scenario `mod` 10) * 0.05 }
      start = initialGameState
        { gameScore = score
        , gameLastBossScore = score
        , gameStatus = Playing
        , gamePipes = []
        , gameTraps = []
        , gameCoins = []
        , gameItems = []
        , gameBoss = Just boss1
        }
      baseY = 120 + fromIntegral (scenario `mod` 9) * 45 :: Float
      maxFrames = ceiling (bossTotalTime boss1 * 60) + 120 :: Int

      go :: Int -> GameState -> (Int, GameState)
      go n st
        | n >= maxFrames = (n, st)
        | gameStatus st == GameOver = (n, st)
        | gameBoss st == Nothing = (n, st)
        | otherwise = go (n + 1) (stepGame (botInput baseY st) st)

      (frames, final) = go 0 start
  in BossSimResult
       { bossScenarioId = scenario
       , bossRoundNo = roundNo
       , bossSurvived = gameStatus final /= GameOver && gameBoss final == Nothing
       , bossFramesUsed = frames
       }

-- Bot đơn giản: treo quanh baseY, né quả lửa sắp tới nếu nó quá gần.
botInput :: Float -> GameState -> Input
botInput baseY st
  | birdY bird > target && birdVelocity bird >= 0 = Flap
  | otherwise = NoInput
  where
    bird = gameBird st
    threats =
      [ t | t <- gameTraps st
          , trapKind t == Fireball
          , trapX t > birdX bird - 20
          , trapX t < birdX bird + 300
          , abs (trapY t - baseY) < 50 ]
    target = case threats of
      []    -> baseY
      (t:_) -> if trapY t >= baseY then max 40 (trapY t - 80)
                                   else min 560 (trapY t + 80)

runBossSequential :: Int -> Int -> [BossSimResult]
runBossSequential roundNo count =
  map (runBossScenario roundNo) [1 .. max 0 count]

runBossParallel :: Int -> Int -> [BossSimResult]
runBossParallel roundNo count =
  parMap rdeepseq (runBossScenario roundNo) [1 .. max 0 count]