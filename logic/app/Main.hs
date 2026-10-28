{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import Control.Monad.IO.Class (liftIO)
import System.Random (randomRIO)
import ApiJSON ()
import Data.Aeson (FromJSON, ToJSON, object, (.=), (.:), (.:?), (.!=), withObject)
import qualified Data.Aeson as Aeson
import Data.Maybe (fromMaybe)
import GameLoop (initialGameState, stepGame, timeStep)
import GameState
import Control.Monad (when)
import Leaderboard
  ( LeaderboardEntry(..)
  , recordScore
  , getTop10
  )
import Achievement
  ( getAchievementStats
  , recordFinishedGame
  )
import Control.DeepSeq (NFData, force)
import Control.Exception (evaluate)
import GHC.Clock (getMonotonicTimeNSec)
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

-- Accept the API request shape used by the frontend: {stepSeconds,input,state}.
-- stepSeconds is converted to a bounded number of the source game's fixed 1/60s ticks.
data StepRequest = StepRequest
  { stepSeconds      :: Maybe Float
  , requestInput     :: Input
  , requestState     :: GameState
  , requestPlayerName :: Maybe String
  }

instance FromJSON StepRequest where
  parseJSON = withObject "StepRequest" $ \o -> StepRequest
    <$> o .:? "stepSeconds"
    <*> o .: "input"
    <*> o .: "state"
    <*> o .:? "playerName"
    
-- Body tùy chọn của /game/start và /game/restart: {"bird":"classic|neon|cyber"}.
-- Body rỗng {} vẫn hợp lệ (dùng chim classic).
data StartRequest = StartRequest
  { startBird :: Maybe String
  , startImmortal :: Maybe Bool   -- true = chế độ bất tử (test)
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
  { simulationCount :: Int
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


-- Tao trang thai moi voi Coin, Shield va WindCurse.
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
        
    filterEvenIndexed pipes =
        [ pipe
        | (index, pipe) <- zip [0 :: Int ..] pipes
        , even index
        ]

-- Đo thời gian chạy và buộc kết quả được tính đầy đủ.
benchmark :: NFData a => IO a -> IO (a, Double)
benchmark action = do
    start <- getMonotonicTimeNSec
    result <- action >>= evaluate . force
    end <- getMonotonicTimeNSec

    let elapsedMs =
            fromIntegral (end - start) / 1000000.0

    return (result, elapsedMs)

main :: IO ()
main = scotty 3000 $ do
  middleware $ cors (const $ Just corsPolicy)

  get "/api/health" $ json (object
    [ "ok" .= True
    , "service" .= ("flappy-bird-haskell" :: String)
    ])
  get "/api/achievements" $ do
    stats <- liftIO getAchievementStats
    json stats
  
  get "/api/leaderboard" $ do
    entries <- liftIO getTop10

    json $ object
      [ "count" .= length entries
      , "entries" .=
          [ object
              [ "rank"  .= rank
              , "name"  .= playerName entry
              , "score" .= playerScore entry
              , "date"  .= playedAt entry
              , "avatar" .=
                  take 1 (playerName entry)
              ]
          | (rank, entry) <- zip [1 :: Int ..] entries
          ]
      ]

  post "/api/game/start" $ do
    req <- jsonData
    state <- liftIO (newRandomGameState (startBird req) (fromMaybe False (startImmortal req)))
    json state

  post "/api/game/step" $ do
    req <- jsonData
    let seconds = max 0 (min 0.25 (fromMaybe timeStep (stepSeconds req)))
        ticks = max 1 (min 15 (round (seconds / timeStep)))
        firstState = stepGame (requestInput req) (requestState req)
        finalState = foldl (\st _ -> stepGame NoInput st) firstState [2 .. ticks]
    let wasGameOver =
          gameStatus (requestState req) == GameOver

        isNowGameOver =
          gameStatus finalState == GameOver

    when (not wasGameOver && isNowGameOver) $ do
        let name = fromMaybe "PLAYER" (requestPlayerName req)
        _ <- liftIO $ recordScore name (gameScore finalState)
        _ <- liftIO $ recordFinishedGame (gameScore finalState)
        pure ()
    json finalState



  post "/api/game/restart" $ do
    req <- jsonData
    state <- liftIO (newRandomGameState (startBird req) (fromMaybe False (startImmortal req)))
    json (state { gameStatus = Playing })

  post "/api/simulation/run" $ do
    req <- jsonData

    let count = max 0 (min 5000 (simulationCount req))
        frames = max 0 (min 100000 (simulationFrames req))

    (sequentialResults, sequentialMs) <-
      liftIO $ benchmark $ evaluate (runSequential count frames)

    (parallelResults, parallelMs) <-
      liftIO $ benchmark $ evaluate (runParallel count frames)

    let speedup
          | parallelMs > 0 = sequentialMs / parallelMs
          | otherwise = 0

    json $ object
      [ "mode" .= ("parallel" :: String)
      , "count" .= count
      , "framesPerScenario" .= frames
      , "results" .= parallelResults
      , "matchesSequential" .=
          (parallelResults == sequentialResults)
      , "benchmark" .= object
          [ "sequentialMs" .= sequentialMs
          , "parallelMs" .= parallelMs
          , "speedup" .= speedup
          ]
      ]

  post "/api/boss/simulate" $ do
    req <- jsonData

    let roundNo = max 1 (min 20 (bossSimRound req))
        count = max 0 (min 5000 (bossSimCount req))

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
      
corsPolicy :: CorsResourcePolicy
corsPolicy = simpleCorsResourcePolicy
  { corsOrigins = Just
      (["http://localhost:5501", "http://127.0.0.1:5501", "http://localhost:5502"], False)
  , corsMethods = ["GET", "POST", "OPTIONS"]
  , corsRequestHeaders = ["Content-Type", "Accept"]
  }