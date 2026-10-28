module Stage
  ( Stage(..)
  , stageForScore
  ) where

import GameState (PipeKind(..), TrapKind(..))

data Stage = Stage
  { stName        :: String
  , stSpeed       :: Double              -- tốc độ cuộn (px/s)
  , stGap         :: Double              -- chiều cao khe của stage
  , stPipeWeights :: [(PipeKind, Int)]   -- trọng số loại ống
  , stTrapChance  :: Double              -- xác suất sinh bẫy (0..1)
  , stTrapWeights :: [(TrapKind, Int)]   -- trọng số loại bẫy
  } deriving (Show, Eq)

-- Mốc điểm và độ khó: rừng, sa mạc, băng, không gian, núi lửa.
stages :: [(Int, Stage)]
stages =
  [ (0, Stage "forest" 130 160
        [(NormalPipe, 1)]
        0.35
        [(CeilingSpikes, 1), (FloorSpikes, 1)])

  , (10, Stage "desert" 145 150
        [(NormalPipe, 3), (MovingPipe, 2)]
        0.60
        [(CeilingSpikes, 1), (FloorSpikes, 1)])

  , (20, Stage "ice" 160 140
        [(NormalPipe, 2), (MovingPipe, 1), (ShrinkingPipe, 2)]
        0.65
        [ (CeilingSpikes, 1), (FloorSpikes, 1)])

  , (30, Stage "space" 175 130
        [(NormalPipe, 2), (ShrinkingPipe, 1), (VanishingPipe, 2)]
        0.70
        [(HunterBird, 1), (CeilingSpikes, 1), (FloorSpikes, 1)])

  , (40, Stage "volcano" 190 120
        [(NormalPipe, 1), (MovingPipe, 1), (ShrinkingPipe, 1), (VanishingPipe, 1)]
        0.80
        [(Fireball, 2), (CeilingSpikes, 1), (FloorSpikes, 1),
        (HunterBird, 1)])
  ]


-- Độ khó tăng theo điểm: tốc độ không giảm, khe không tăng.
stageForScore :: Int -> Stage
stageForScore score = foldl choose (snd (head stages)) stages
  where
    choose current (threshold, candidate)
      | score >= threshold = candidate
      | otherwise = current
