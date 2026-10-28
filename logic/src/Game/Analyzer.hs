{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
-- | Kiến trúc tổng thể:
--
-- >                GameState
-- >               /         \
-- >   Nhánh A: Danger     Nhánh B: Rage & Skill      <- chạy SONG SONG (rpar)
-- >               \         /
-- >        Decision & Warning Engine
-- >                  |
-- >      JSON API -> Frontend JavaScript
module Analyzer
  ( AnalyzerInput(..)
  , DangerReport(..)
  , RageReport(..)
  , rageMax
  , ragePerPipe
  , analyzeDanger
  , analyzeRage
  , decide
  , analyzeParallel
  , analyzeSequential
  ) where

import Control.DeepSeq (NFData, force)
import Control.Parallel.Strategies (rpar, rseq, runEval)
import GHC.Generics (Generic)
import GameState
import Geometry (Shape(..), pipeShapes, trapShape)

-- ---------------------------------------------------------------------------
-- Hằng số
-- ---------------------------------------------------------------------------

-- | Thanh nộ 0..100, mỗi cột vượt qua hợp lệ +20 => đúng 5 cột thì đầy.
rageMax, ragePerPipe :: Int
rageMax = 100
ragePerPipe = 20

-- | Nhìn trước bao nhiêu tick (45 tick = 0.75 giây thật ở 60 FPS).
horizonTicks :: Int
horizonTicks = 45

tickSeconds :: Float
tickSeconds = 1 / 60

-- ---------------------------------------------------------------------------
-- Đầu vào / đầu ra của hai nhánh
-- ---------------------------------------------------------------------------

data AnalyzerInput = AnalyzerInput
  { aiStepBird    :: Bird -> Bird  -- ^ vật lý chim cho 1 tick (không flap thêm)
  , aiScroll      :: Float         -- ^ tốc độ cuộn thế giới (đã nhân speedMul)
  , aiWorldDt     :: Float         -- ^ dt của thế giới trong 1 tick
  , aiPipesPassed :: Int           -- ^ số cột vừa vượt qua trong frame này
  }

data DangerReport = DangerReport
  { drLevel    :: DangerLevel
  , drTimeToHit :: Float           -- giây, -1 nếu không dự đoán va chạm
  , drDistance :: Float            -- px tới vật cản gần nhất phía trước, -1 nếu không có
  , drThreat   :: String
  } deriving (Show, Eq, Generic, NFData)

data RageReport = RageReport
  { rrRage        :: Int
  , rrPipesToFull :: Int
  , rrSkillReady  :: Bool
  , rrSkillActive :: Bool
  , rrTimeLeft    :: Float
  } deriving (Show, Eq, Generic, NFData)

-- ---------------------------------------------------------------------------
-- Nhánh A: Danger Analyzer
-- Đo khoảng cách, dự đoán va chạm bằng cách mô phỏng quỹ đạo chim trong
-- vài tick tới (chim cứ rơi theo trọng lực, không flap thêm).
-- ---------------------------------------------------------------------------

analyzeDanger :: AnalyzerInput -> GameState -> DangerReport
analyzeDanger ai st =
  case firstHit of
    Nothing ->
      DangerReport Safe (-1) distance ""
    Just (k, what) ->
      let t = fromIntegral k * tickSeconds
          level
            | t < 0.25  = Critical
            | t < 0.50  = Danger
            | otherwise = Caution
      in DangerReport level t distance what
  where
    params = gameParams st
    bird0  = gameBird st

    -- Quỹ đạo dự đoán của chim: tick 1, 2, 3, ...
    futureBirds = zip [1 :: Int ..] (take horizonTicks (tail (iterate (aiStepBird ai) bird0)))

    firstHit =
      case [ (k, w) | (k, b) <- futureBirds, Just w <- [hitAt k b] ] of
        []      -> Nothing
        (h : _) -> Just h

    hitAt :: Int -> Bird -> Maybe String
    hitAt k b
      | hitsBoundary b                                        = Just "boundary"
      | any (circleHits b . pipeShapes params . shiftPipe k)
            (gamePipes st)                                    = Just "pipe"
      | any (maybe False (circleHit b) . trapShape params . shiftTrap k)
            (gameTraps st)                                    = Just "trap"
      | otherwise                                             = Nothing

    hitsBoundary b =
      birdY b - birdRadius b <= 0
        || birdY b + birdRadius b >= realToFrac (screenH params)

    elapsed k = fromIntegral k * aiWorldDt ai

    shiftPipe k p = p
      { pipeX = pipeX p - aiScroll ai * elapsed k
      , pipeAge = pipeAge p + elapsed k
      }

    shiftTrap k t = t
      { trapX = trapX t - (aiScroll ai + extraTrapSpeed t) * elapsed k }

    extraTrapSpeed t = case trapKind t of
      Fireball   -> realToFrac (fireballSpeed params)
      HunterBird -> realToFrac (hunterSpeed params)
      _          -> 0

    -- Khoảng cách ngang tới vật cản gần nhất còn ở phía trước chim.
    distance =
      case pipeDists ++ trapDists of
        [] -> -1
        ds -> minimum ds
    pipeDists =
      [ max 0 (pipeX p - birdX bird0)
      | p <- gamePipes st
      , not (pipeBroken p)
      , pipeX p + pipeWidth p >= birdX bird0 ]
    trapDists =
      [ max 0 (trapX t - birdX bird0)
      | t <- gameTraps st
      , trapActive t
      , trapKind t /= StrongWind
      , trapX t + trapRadius t >= birdX bird0 ]

-- Chim (hình tròn) chạm hình chữ nhật / hình tròn.
circleHits :: Bird -> [Shape] -> Bool
circleHits b = any (circleHit b)

circleHit :: Bird -> Shape -> Bool
circleHit bird (Rect x y w h) =
  let bx = realToFrac (birdX bird)
      by = realToFrac (birdY bird)
      r  = realToFrac (birdRadius bird)
      closestX = max x (min bx (x + w))
      closestY = max y (min by (y + h))
      dx = bx - closestX
      dy = by - closestY
  in dx * dx + dy * dy <= r * r
circleHit bird (Circle x y r) =
  let dx = realToFrac (birdX bird) - x
      dy = realToFrac (birdY bird) - y
      tr = realToFrac (birdRadius bird) + r
  in dx * dx + dy * dy <= tr * tr

-- ---------------------------------------------------------------------------
-- Nhánh B: Rage & Skill Engine
-- Cộng nộ khi qua cột; xác định skill đã sẵn sàng chưa.
-- Chim thường (NoSkill) không có cơ chế nộ / skill.
-- ---------------------------------------------------------------------------

analyzeRage :: AnalyzerInput -> GameState -> RageReport
analyzeRage ai st =
  RageReport
    { rrRage        = rage'
    , rrPipesToFull = pipesToFull
    , rrSkillReady  = full && not active
    , rrSkillActive = active
    , rrTimeLeft    = if active then birdSkillDuration bird else 0
    }
  where
    bird     = gameBird st
    hasSkill = birdSkill bird /= NoSkill
    gain     = if hasSkill then ragePerPipe * aiPipesPassed ai else 0
    rage'    = if hasSkill then min rageMax (gameRage st + gain) else 0
    full     = hasSkill && rage' >= rageMax
    active   = hasSkill && birdSkillDuration bird > 0
    pipesToFull
      | hasSkill  = (rageMax - rage' + ragePerPipe - 1) `div` ragePerPipe
      | otherwise = 0

-- ---------------------------------------------------------------------------
-- Decision & Warning Engine
-- Kết hợp mức nguy hiểm + thanh nộ + trạng thái của người chơi
-- (đang được bảo vệ bởi khiên / skill thì không cần báo đỏ).
-- ---------------------------------------------------------------------------

decide :: GameState -> DangerReport -> RageReport -> Decision
decide st d r = Decision
  { decRage          = rrRage r
  , decRageFull      = hasSkill && rrRage r >= rageMax
  , decPipesToFull   = rrPipesToFull r
  , decSkillReady    = rrSkillReady r
  , decSkillActive   = rrSkillActive r
  , decSkillTimeLeft = rrTimeLeft r
  , decDangerLevel   = drLevel d
  , decTimeToHit     = drTimeToHit d
  , decNearestDistance = drDistance d
  , decThreat        = drThreat d
  , decWarningRed    = urgent
  , decSuggestSkill  = urgent && rrSkillReady r
  }
  where
    bird     = gameBird st
    hasSkill = birdSkill bird /= NoSkill
    urgent   = drLevel d >= Danger && not (protectedFrom (drThreat d))

    skillOn s = birdSkill bird == s && birdSkillDuration bird > 0
    shielded  = any isShield (gameEffects st)
    isShield (ShieldEffect t) = t > 0
    isShield _ = False

    protectedFrom "pipe"     = gameImmortal st || shielded || skillOn PassThroughPipe || skillOn Dash
    protectedFrom "trap"     = gameImmortal st || skillOn Invisibility || skillOn Dash
    protectedFrom "boundary" = skillOn Dash
    protectedFrom _          = False

-- ---------------------------------------------------------------------------
-- Chạy hai nhánh SONG SONG rồi gộp lại.
-- Cần build với -threaded và chạy với +RTS -N để thật sự dùng nhiều lõi.
-- ---------------------------------------------------------------------------

analyzeParallel :: AnalyzerInput -> GameState -> Decision
analyzeParallel ai st = decide st danger rage
  where
    (danger, rage) = runEval $ do
      a <- rpar (force (analyzeDanger ai st))   -- nhánh A
      b <- rpar (force (analyzeRage ai st))     -- nhánh B
      _ <- rseq a
      _ <- rseq b
      return (a, b)

-- | Bản tuần tự, dùng để so sánh / benchmark với bản song song.
analyzeSequential :: AnalyzerInput -> GameState -> Decision
analyzeSequential ai st =
  decide st (analyzeDanger ai st) (analyzeRage ai st)