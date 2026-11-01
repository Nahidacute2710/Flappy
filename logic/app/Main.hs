
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Concurrent.MVar (newMVar, withMVar)
import Control.DeepSeq (NFData, force)
import Control.Exception (evaluate)
import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import System.Random (randomRIO)

import ApiJSON ()
import CommandParser (parseSimulationCommand, SimulationConfig(..))
import Data.Aeson (FromJSON, ToJSON, object, (.=), (.:), (.:?), (.!=), withObject)
import qualified Data.Aeson as Aeson
import Data.Maybe (fromMaybe)
import GameLoop (initialGameState, stepGame, timeStep)
import GameState
import GHC.Clock (getMonotonicTimeNSec)

import Leaderboard
  ( LeaderboardEntry(..)
  , recordScore
  , getTop10
  )

import Achievement
  ( getAchievementStats
  , recordFinishedGame
  )

import Network.Wai.Middleware.Cors
  ( CorsResourcePolicy(..)
  , cors
  , simpleCorsResourcePolicy
  )

import Simulation
  ( BossSimResult(..)
  , runParallel
  , runSequential
  , runBossParallel
  , runBossSequential
  )

import Web.Scotty

-- Du lieu gui tu frontend khi cap nhat game.
data StepRequest = StepRequest
  { stepSeconds       :: Maybe Float
  , requestInput      :: Input
  , requestState      :: GameState
  , requestPlayerName :: Maybe String
  }

instance FromJSON StepRequest where
  parseJSON = withObject "StepRequest" $ \o -> StepRequest
    <$> o .:? "stepSeconds"
    <*> o .: "input"
    <*> o .: "state"
    <*> o .:? "playerName"

-- Cau hinh khi bat dau hoac choi lai.
data StartRequest = StartRequest
  { startBird     :: Maybe String
  , startImmortal :: Maybe Bool
  }

instance FromJSON StartRequest where
  parseJSON = withObject "StartRequest" $ \o -> StartRequest
    <$> o .:? "bird"
    <*> o .:? "immortal"

data BossSimRequest = BossSimRequest
  { bossSimRound :: Int
  , bossSimCount :: Int
  }

instance FromJSON BossSimRequest where
  parseJSON = withObject "BossSimRequest" $ \o -> BossSimRequest
    <$> (o .:? "round" .!= 1)
    <*> (o .:? "count" .!= 200)

data SimulationRequest = SimulationRequest
  { simulationCount  :: Int
  , simulationFrames :: Int
  }

instance FromJSON SimulationRequest where
  parseJSON = withObject "SimulationRequest" $ \o -> SimulationRequest
    <$> (o .:? "count" .!= 100)
    <*> (o .:? "framesPerScenario" .!= 600)

instance ToJSON SimulationRequest where
  toJSON req = object
    [ "count" .= simulationCount req
    , "framesPerScenario" .= simulationFrames req
    ]

newtype SimulationCommandRequest =
  SimulationCommandRequest
    { commandText :: String
    }

instance FromJSON SimulationCommandRequest where
  parseJSON = withObject "SimulationCommandRequest" $ \o ->
    SimulationCommandRequest <$> o .: "command"

-- Tao trang thai game voi Coin, Shield va WindCurse.
newRandomGameState :: Maybe String -> Bool -> IO GameState
newRandomGameState skin immortal = do
  let base = initialGameState
        { gameBird = birdForSkin (fromMaybe "classic" skin)
        , gameImmortal = immortal
        }

      pipes = gamePipes base

  coins <- mapM makeCoin pipes
  shields <- mapM makeShield (filterEvenIndexed pipes)

  let windPipes = drop 1 (filterEvenIndexed pipes)

  windCurses <- mapM makeWindCurse windPipes

  let items = shields ++ windCurses

  return base
    { gameCoins = coins
    , gameItems = items
    }

  where
    makeCoin pipe = do
      y <- randomY pipe
      return $ Coin
        (pipeX pipe + pipeWidth pipe / 2)
        y
        9
        GoldCoin
        False

    makeShield pipe = do
      y <- randomY pipe
      return $ ItemPickup
        (pipeX pipe + pipeWidth pipe / 2)
        y
        13
        Shield
        False

    makeWindCurse pipe = do
      y <- randomY pipe
      return $ ItemPickup
        (pipeX pipe + pipeWidth pipe / 2)
        y
        18
        WindCurse
        False

    randomY pipe =
      let top = pipeGapTop pipe
          bottom = pipeGapBottom pipe
          low = min (top + 20) (bottom - 20)
          high = max (top + 20) (bottom - 20)
      in randomRIO (low, high)

    filterEvenIndexed ps =
      [ pipe
      | (index, pipe) <- zip [0 :: Int ..] ps
      , even index
      ]

-- Do thoi gian xu ly va danh gia ket qua day du.
benchmark :: NFData a => IO a -> IO (a, Double)
benchmark action = do
  start <- getMonotonicTimeNSec

  result <- action >>= evaluate . force

  end <- getMonotonicTimeNSec

  let elapsedMs =
        fromIntegral (end - start) / 1000000.0

  return (result, elapsedMs)

main :: IO ()
main = do

  -- Khoa dong bo dung chung cho cac request.
  -- Bao ve viec doc va ghi diem, thanh tich.
  persistenceLock <- newMVar ()

  scotty 3000 $ do

    middleware $ cors (const $ Just corsPolicy)

    -- Kiem tra backend.
    get "/api/health" $ do
      json $ object
        [ "ok" .= True
        , "service" .= ("flappy-bird-haskell" :: String)
        ]

    -- Lay thong ke thanh tich.
    get "/api/achievements" $ do
      stats <- liftIO $
        withMVar persistenceLock (const getAchievementStats)

      json stats

    -- Lay bang xep hang.
    get "/api/leaderboard" $ do
      entries <- liftIO $
        withMVar persistenceLock (const getTop10)

      json $ object
        [ "count" .= length entries
        , "entries" .=
            [ object
                [ "rank" .= rank
                , "name" .= playerName entry
                , "score" .= playerScore entry
                , "date" .= playedAt entry
                , "avatar" .= take 1 (playerName entry)
                ]
            | (rank, entry) <- zip [1 :: Int ..] entries
            ]
        ]

    -- Bat dau van choi moi.
    post "/api/game/start" $ do
      req <- jsonData

      state <- liftIO $
        newRandomGameState
          (startBird req)
          (fromMaybe False (startImmortal req))

      json state

    -- Cap nhat trang thai game.
    post "/api/game/step" $ do
      req <- jsonData

      let seconds =
            max 0 (min 0.25 (fromMaybe timeStep (stepSeconds req)))

          ticks =
            max 1 (min 15 (round (seconds / timeStep)))

          firstState =
            stepGame (requestInput req) (requestState req)

          finalState =
            foldl
              (\st _ -> stepGame NoInput st)
              firstState
              [2 .. ticks]

          wasGameOver =
            gameStatus (requestState req) == GameOver

          isNowGameOver =
            gameStatus finalState == GameOver

      -- Chi luu khi trang thai chuyen sang GameOver.
      when (not wasGameOver && isNowGameOver) $ do
        let name = fromMaybe "PLAYER" (requestPlayerName req)

        liftIO $ withMVar persistenceLock $ const $ do
          _ <- recordScore name (gameScore finalState)
          _ <- recordFinishedGame (gameScore finalState)
          pure ()

      json finalState

    -- Khoi dong lai van choi.
    post "/api/game/restart" $ do
      req <- jsonData

      state <- liftIO $
        newRandomGameState
          (startBird req)
          (fromMaybe False (startImmortal req))

      json (state { gameStatus = Playing })

    -- Doc lenh mo phong bang parser combinator.
    post "/api/simulation/command" $ do
      body <- jsonData :: ActionM Aeson.Value

      case Aeson.fromJSON body :: Aeson.Result SimulationCommandRequest of

        Aeson.Error err ->
          json $ object
            [ "ok" .= False
            , "error" .= err
            ]

        Aeson.Success commandReq ->
          case parseSimulationCommand (commandText commandReq) of

            Left err ->
              json $ object
                [ "ok" .= False
                , "error" .= err
                ]

            Right cfg -> do
              let simulationResult =
                    if mode cfg == "parallel"
                      then runParallel (runs cfg) (frames cfg)
                      else runSequential (runs cfg) (frames cfg)

              (results, ms) <-
                liftIO $ benchmark $ evaluate simulationResult

              json $ object
                [ "ok" .= True
                , "mode" .= mode cfg
                , "count" .= runs cfg
                , "framesPerScenario" .= frames cfg
                , "elapsedMs" .= ms
                , "results" .= results
                ]

    -- So sanh mo phong tuan tu va song song.
    post "/api/simulation/run" $ do
      req <- jsonData

      let count =
            max 0 (min 5000 (simulationCount req))

          frameCount =
            max 0 (min 100000 (simulationFrames req))

      (sequentialResults, sequentialMs) <-
        liftIO $ benchmark $ evaluate
          (runSequential count frameCount)

      (parallelResults, parallelMs) <-
        liftIO $ benchmark $ evaluate
          (runParallel count frameCount)

      let speedup
            | parallelMs > 0 = sequentialMs / parallelMs
            | otherwise = 0

      json $ object
        [ "mode" .= ("parallel" :: String)
        , "count" .= count
        , "framesPerScenario" .= frameCount
        , "results" .= parallelResults
        , "matchesSequential" .=
            (parallelResults == sequentialResults)
        , "benchmark" .= object
            [ "sequentialMs" .= sequentialMs
            , "parallelMs" .= parallelMs
            , "speedup" .= speedup
            ]
        ]

    -- Mo phong boss bang xu ly song song.
    post "/api/boss/simulate" $ do
      req <- jsonData

      let roundNo =
            max 1 (min 20 (bossSimRound req))

          count =
            max 0 (min 5000 (bossSimCount req))

      (sequentialResults, sequentialMs) <-
        liftIO $ benchmark $ evaluate
          (runBossSequential roundNo count)

      (parallelResults, parallelMs) <-
        liftIO $ benchmark $ evaluate
          (runBossParallel roundNo count)

      let survived =
            length (filter bossSurvived parallelResults)

          speedup
            | parallelMs > 0 = sequentialMs / parallelMs
            | otherwise = 0

      json $ object
        [ "mode" .= ("parallel" :: String)
        , "round" .= roundNo
        , "count" .= count
        , "survived" .= survived
        , "matchesSequential" .=
            (parallelResults == sequentialResults)
        , "benchmark" .= object
            [ "sequentialMs" .= sequentialMs
            , "parallelMs" .= parallelMs
            , "speedup" .= speedup
            ]
        ]

-- Cau hinh cho phep frontend ket noi backend.
corsPolicy :: CorsResourcePolicy
corsPolicy = simpleCorsResourcePolicy
  { corsOrigins = Just
      ( [ "http://localhost:5501"
        , "http://127.0.0.1:5501"
        , "http://localhost:5502"
        ]
      , False
      )
  , corsMethods = ["GET", "POST", "OPTIONS"]
  , corsRequestHeaders = ["Content-Type", "Accept"]
  }
