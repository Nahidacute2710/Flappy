
{-# LANGUAGE DeriveGeneric #-}

module Leaderboard
  ( LeaderboardEntry(..)
  , recordScore
  , getTop10
  ) where

import Control.Exception (throwIO)
import Data.Aeson (FromJSON(..), ToJSON(..), eitherDecodeFileStrict')
import Data.List (sortOn)
import Data.Ord (Down(..))
import Data.Time (getCurrentTime)
import GHC.Generics (Generic)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath ((</>))

import StorageFile (writeJsonAtomic)

-- Một bản ghi điểm của một lượt chơi.
data LeaderboardEntry = LeaderboardEntry
  { playerName  :: String
  , playerScore :: Int
  , playedAt    :: String
  } deriving (Show, Eq, Generic)

instance ToJSON LeaderboardEntry
instance FromJSON LeaderboardEntry

leaderboardFile :: FilePath
leaderboardFile = "data" </> "leaderboard.json"

-- Đọc bảng xếp hạng.
-- Tệp chưa tồn tại thì trả danh sách rỗng.
-- Tệp tồn tại nhưng JSON không hợp lệ thì báo lỗi.
readEntries :: IO [LeaderboardEntry]
readEntries = do
  exists <- doesFileExist leaderboardFile

  if not exists
    then pure []
    else do
      result <- eitherDecodeFileStrict' leaderboardFile

      case result of
        Left err ->
          throwIO $ userError $
            "Khong the doc leaderboard.json: " ++ err

        Right entries ->
          pure entries

-- Lấy tối đa 10 lượt chơi có điểm cao nhất.
getTop10 :: IO [LeaderboardEntry]
getTop10 = do
  entries <- readEntries

  pure $
    take 10 $
      sortOn (Down . playerScore) entries

-- Lưu điểm mới và cập nhật Top 10.
-- Việc đồng bộ giữa các request do MVar trong Main.hs đảm nhiệm.
recordScore :: String -> Int -> IO [LeaderboardEntry]
recordScore name score = do
  createDirectoryIfMissing True "data"

  oldEntries <- readEntries
  now <- getCurrentTime

  let cleanName =
        if null (trim name)
          then "PLAYER"
          else trim name

      newEntry = LeaderboardEntry
        { playerName = take 20 cleanName
        , playerScore = max 0 score
        , playedAt = show now
        }

      topEntries =
        take 10 $
          sortOn (Down . playerScore)
            (newEntry : oldEntries)

  writeJsonAtomic leaderboardFile topEntries

  pure topEntries

-- Bỏ khoảng trắng ở đầu và cuối tên.
trim :: String -> String
trim = dropWhileEnd isSpace . dropWhile isSpace
  where
    isSpace c =
      c == ' ' || c == '\t' || c == '\n' || c == '\r'

    dropWhileEnd f =
      reverse . dropWhile f . reverse
