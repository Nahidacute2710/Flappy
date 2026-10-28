
{-# LANGUAGE DeriveGeneric #-}

module Leaderboard
  ( LeaderboardEntry(..)
  , recordScore
  , getTop10
  ) where

import Control.Exception (IOException, catch)
import Data.Aeson
import Data.List (sortOn)
import Data.Ord (Down(..))
import Data.Time (getCurrentTime)
import GHC.Generics (Generic)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))

-- Một bản ghi của một lượt chơi.
data LeaderboardEntry = LeaderboardEntry
  { playerName  :: String
  , playerScore :: Int
  , playedAt    :: String
  } deriving (Show, Eq, Generic)

instance ToJSON LeaderboardEntry where
  toJSON = genericToJSON defaultOptions

instance FromJSON LeaderboardEntry where
  parseJSON = genericParseJSON defaultOptions

leaderboardFile :: FilePath
leaderboardFile = "data" </> "leaderboard.json"

-- Đọc dữ liệu đã lưu. Nếu file chưa tồn tại hoặc chưa đọc được,
-- trả về danh sách rỗng.
readEntries :: IO [LeaderboardEntry]
readEntries =
  (do
      content <- eitherDecodeFileStrict' leaderboardFile
      pure (either (const []) id content)
  ) `catch` handleReadError
  where
    handleReadError :: IOException -> IO [LeaderboardEntry]
    handleReadError _ = pure []

-- Lấy tối đa 10 lượt chơi có điểm cao nhất.
getTop10 :: IO [LeaderboardEntry]
getTop10 = do
  entries <- readEntries
  pure $ take 10 $
    sortOn (\entry -> Down (playerScore entry)) entries

-- Lưu điểm mới, sắp xếp lại và chỉ giữ Top 10.
recordScore :: String -> Int -> IO [LeaderboardEntry]
recordScore name score = do
  createDirectoryIfMissing True "data"

  oldEntries <- readEntries
  now <- getCurrentTime

  let cleanName =
        if null (trim name) then "PLAYER" else trim name

      newEntry = LeaderboardEntry
        { playerName = take 20 cleanName
        , playerScore = max 0 score
        , playedAt = show now
        }

      topEntries = take 10 $
        sortOn (\entry -> Down (playerScore entry))
          (newEntry : oldEntries)

  encodeFile leaderboardFile topEntries
  pure topEntries

trim :: String -> String
trim = dropWhileEnd isSpace . dropWhile isSpace
  where
    isSpace c = c == ' ' || c == '\t' || c == '\n' || c == '\r'
    dropWhileEnd f = reverse . dropWhile f . reverse
