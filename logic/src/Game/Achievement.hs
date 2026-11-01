
{-# LANGUAGE DeriveGeneric #-}

module Achievement
  ( AchievementStats(..)
  , getAchievementStats
  , recordFinishedGame
  ) where

import Control.Exception (throwIO)
import Data.Aeson
  ( FromJSON
  , ToJSON
  , eitherDecodeFileStrict'
  )
import GHC.Generics (Generic)
import System.Directory
  ( createDirectoryIfMissing
  , doesFileExist
  )

import StorageFile (writeJsonAtomic)

-- Thong ke tong the cua nguoi choi.
data AchievementStats = AchievementStats
  { totalGames :: Int
  , bestScore  :: Int
  , totalScore :: Int
  } deriving (Show, Generic)

instance ToJSON AchievementStats
instance FromJSON AchievementStats

-- Trang thai ban dau khi chua co du lieu.
emptyStats :: AchievementStats
emptyStats = AchievementStats
  { totalGames = 0
  , bestScore = 0
  , totalScore = 0
  }

statsFile :: FilePath
statsFile = "data/achievements.json"

-- Doc du lieu thong ke tu JSON.
-- Neu tep chua ton tai, tra ve thong ke ban dau.
-- Neu JSON khong hop le, bao loi thay vi xoa du lieu cu.
getAchievementStats :: IO AchievementStats
getAchievementStats = do
  exists <- doesFileExist statsFile

  if not exists
    then pure emptyStats
    else do
      result <- eitherDecodeFileStrict' statsFile

      case result of
        Left err ->
          throwIO $ userError $
            "Khong the doc achievements.json: " ++ err

        Right stats ->
          pure stats

-- Cap nhat thong ke khi mot van choi ket thuc.
-- Viec dong bo giua cac request do MVar trong Main.hs xu ly.
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

  writeJsonAtomic statsFile newStats

  pure newStats
