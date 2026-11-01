
module Main (main) where

import Achievement
  ( AchievementStats(..)
  , getAchievementStats
  , recordFinishedGame
  )
import Leaderboard
  ( LeaderboardEntry(..)
  , getTop10
  , recordScore
  )

import Control.Concurrent (forkIO)
import Control.Concurrent.Chan (newChan, readChan, writeChan)
import Control.Concurrent.MVar (newMVar, withMVar)
import Control.Exception (SomeException, bracket, try)
import Control.Monad (forM_, replicateM)
import System.Directory
  ( createDirectory
  , getTemporaryDirectory
  , removeFile
  , removePathForcibly
  , withCurrentDirectory
  )
import System.Exit (exitFailure)
import System.IO (hClose, openTempFile)

-- Tao thu muc rieng de khong anh huong du lieu game that.
createTestDirectory :: IO FilePath
createTestDirectory = do
  tmp <- getTemporaryDirectory
  (path, handle) <- openTempFile tmp "flappy-storage-test-"
  hClose handle
  removeFile path
  createDirectory path
  pure path

-- Kiem tra ket qua sau khi 30 luong hoan thanh.
checkResults :: Int -> Int -> IO ()
checkResults workerCount scorePerGame = do
  stats <- getAchievementStats
  leaderboard <- getTop10

  let expectedGames = workerCount
      expectedScore = workerCount * scorePerGame

      gamesCorrect =
        totalGames stats == expectedGames

      scoreCorrect =
        totalScore stats == expectedScore

      bestCorrect =
        bestScore stats == scorePerGame

      leaderboardCorrect =
        length leaderboard == 10
          && all
               ((== scorePerGame) . playerScore)
               leaderboard

  putStrLn ""
  putStrLn "===== KET QUA KIEM THU ====="
  putStrLn ("So van: " ++ show (totalGames stats))
  putStrLn ("Tong diem: " ++ show (totalScore stats))
  putStrLn ("Diem cao nhat: " ++ show (bestScore stats))
  putStrLn ("So ban ghi Top 10: " ++ show (length leaderboard))

  if gamesCorrect
      && scoreCorrect
      && bestCorrect
      && leaderboardCorrect
    then putStrLn "PASS: 30 luong luu JSON dung, khong mat du lieu."
    else do
      putStrLn "FAIL: Du lieu JSON khong chinh xac."
      exitFailure

-- Chay kiem thu trong thu muc tam.
runTest :: IO ()
runTest = do
  let workerCount = 30
      scorePerGame = 10

  -- Dung chung mot khoa nhu Main.hs.
  persistenceLock <- newMVar ()

  -- Moi luong gui ket qua hoac loi ve luong chinh.
  completed <- newChan

  putStrLn "Dang tao 30 luong ghi du lieu JSON..."

  forM_ [1 .. workerCount] $ \i -> do
    _ <- forkIO $ do
      result <- try $
        withMVar persistenceLock $ \_ -> do
          let name = "PLAYER" ++ show i

          _ <- recordScore name scorePerGame
          _ <- recordFinishedGame scorePerGame

          pure ()

      writeChan completed (result :: Either SomeException ())

    pure ()

  -- Cho du 30 luong va thu thap loi neu co.
  results <- replicateM workerCount (readChan completed)

  let errors = [err | Left err <- results]

  if null errors
    then checkResults workerCount scorePerGame
    else do
      putStrLn "FAIL: Co luong gap loi khi ghi JSON."
      mapM_ print errors
      exitFailure

main :: IO ()
main =
  bracket createTestDirectory removePathForcibly $ \testDir ->
    withCurrentDirectory testDir runTest
