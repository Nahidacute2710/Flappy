
module StorageFile
  ( writeJsonAtomic
  ) where

import Control.Exception (bracketOnError)
import Data.Aeson (ToJSON, encode)
import qualified Data.ByteString.Lazy as BL
import System.Directory (removeFile, renameFile)
import System.FilePath (takeDirectory, takeFileName)
import System.IO (openBinaryTempFile, hClose, hFlush)
import System.IO.Error (catchIOError)

-- Ghi JSON vao tep tam, sau do thay the tep chinh.
-- Han che nguy co hong du lieu neu qua trinh ghi bi gian doan.
writeJsonAtomic :: ToJSON a => FilePath -> a -> IO ()
writeJsonAtomic filePath value =
  bracketOnError
    (openBinaryTempFile directory template)
    cleanup
    writeAndReplace
  where
    directory = takeDirectory filePath
    template = takeFileName filePath ++ ".tmp"

    cleanup (tempPath, handle) = do
      catchIOError (hClose handle) (\_ -> pure ())
      catchIOError
        (removeTempFile tempPath)
        (\_ -> pure ())

    removeTempFile path = do
      removeFile path

    writeAndReplace (tempPath, handle) = do
      BL.hPut handle (encode value)
      hFlush handle
      hClose handle
      renameFile tempPath filePath
