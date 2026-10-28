module CommandParser
  ( SimulationConfig(..)
  , parseSimulationCommand
  ) where

import Text.Parsec
import Text.Parsec.String (Parser)

data SimulationConfig = SimulationConfig
  { frames :: Int
  , runs   :: Int
  , mode   :: String
  } deriving (Show, Eq)

-- Đọc một số nguyên không âm
integerParser :: Parser Int
integerParser = read <$> many1 digit

-- Đọc một trường có dạng key=value
fieldParser :: String -> Parser Int
fieldParser key = do
  _ <- string key
  _ <- char '='
  integerParser

-- Đọc chế độ mô phỏng
modeParser :: Parser String
modeParser = do
  _ <- string "mode="
  try (string "parallel") <|> string "sequential"

-- Parser cho toàn bộ lệnh mô phỏng
simulationParser :: Parser SimulationConfig
simulationParser = do
  _ <- string "simulate"
  spaces
  f <- fieldParser "frames"
  spaces
  r <- fieldParser "runs"
  spaces
  m <- modeParser
  spaces
  eof

  if f <= 0 || r <= 0
    then fail "frames va runs phai lon hon 0"
    else
      if f > 100000 || r > 5000
        then fail "Vuot gioi han mo phong"
        else pure (SimulationConfig f r m)

parseSimulationCommand
  :: String
  -> Either String SimulationConfig
parseSimulationCommand input =
  case parse simulationParser "simulation command" input of
    Left err  -> Left (show err)
    Right cfg -> Right cfg
