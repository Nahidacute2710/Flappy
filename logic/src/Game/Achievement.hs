
{-# LANGUAGE DeriveGeneric #-}

module Achievement
  ( AchievementStats(..)
  , getAchievementStats
  , recordFinishedGame
  ) where

import Data.Aeson
  ( FromJSON
  , ToJSON
  , decode
  , encode
  )
import qualified Data.ByteString.Lazy as BL
import GHC.Generics (Generic)
import System.Directory
  ( createDirectoryIfMissing
  , doesFileExist
  )

-- Thống kê tổng thể của người chơi
data AchievementStats = AchievementStats
  { totalGames :: Int
  , bestScore  :: Int
  , totalScore :: Int
  } deriving (Show, Generic)

instance ToJSON AchievementStats
instance FromJSON AchievementStats

-- Giá trị ban đầu khi chưa chơi trận nào
emptyStats :: AchievementStats
emptyStats = AchievementStats
  { totalGames = 0
  , bestScore = 0
  , totalScore = 0
  }

statsFile :: FilePath
statsFile = "data/achievements.json"

-- Đọc dữ liệu đã lưu
getAchievementStats :: IO AchievementStats
getAchievementStats = do
  exists <- doesFileExist statsFile

  if not exists
    then pure emptyStats
    else do
      content <- BL.readFile statsFile
      case decode content of
        Just stats -> pure stats
        Nothing    -> pure emptyStats

-- Gọi đúng một lần khi một trận vừa kết thúc
recordFinishedGame :: Int -> IO AchievementStats
recordFinishedGame finalScore = do
  createDirectoryIfMissing True "data"

  oldStats <- getAchievementStats

  let score = max 0 finalScore

      newStats = AchievementStats
        { totalGames = totalGames oldStats + 1
        , bestScore = max (bestScore oldStats) score
        , totalScore = totalScore oldStats + score
        }

  BL.writeFile statsFile (encode newStats)

  pure newStats
