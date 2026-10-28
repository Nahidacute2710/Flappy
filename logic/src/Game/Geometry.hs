module Geometry
  ( Shape(..)
  , pipeGapCenter
  , pipeGapHeight
  , pipeSolid
  , pipeShapes
  , trapShape
  , trapExtent
  ) where

import GameState

data Shape
  = Rect   { sx, sy, sw, sh :: Double }  -- top-left corner + dimensions
  | Circle { cx, cy, cr :: Double }      -- center + radius
  deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Hệ số vùng va chạm (tinh chỉnh ở đây).
-- Giữ cho khớp với hình vẽ bên frontend (funct.js).
-- ---------------------------------------------------------------------------

-- Độ rộng vùng va chạm của cột so với pipeWidth.
-- 1.0 = đúng hình vẽ (frontend cũng đang vẽ cột ở 100%).
pipeHitScale :: Double
pipeHitScale = 1.0

-- Gai: chim phải lún vào khoảng 3/4 chiều cao gai mới tính trúng (mũi gai nhọn nên chừa phần chóp).
spikeHitHeightScale :: Double
spikeHitHeightScale = 0.75

-- Gai: vùng va chạm hẹp hơn thân gai một chút cho dễ chịu.
spikeHitWidthScale :: Double
spikeHitWidthScale = 0.6

-- Cầu lửa / chim săn mồi: 1.0 = đúng hình vẽ.
trapCircleHitScale :: Double
trapCircleHitScale = 1.0

frac :: Double -> Double
frac x = x - fromIntegral (floor x :: Integer)

phaseOf :: Params -> Pipe -> Double
phaseOf p q =
  2 * pi * realToFrac (pipeAge q) / movePeriod p
    + realToFrac (pipePhase q)

gapY :: Pipe -> Double
gapY q = (realToFrac (pipeGapTop q) + realToFrac (pipeGapBottom q)) / 2

pipeGap :: Pipe -> Double
pipeGap q = realToFrac (pipeGapBottom q - pipeGapTop q)

-- Current center of the opening. Animation is derived from pipeAge, not accumulated.
pipeGapCenter :: Params -> Pipe -> Double
pipeGapCenter p q = case pipeKind q of
  MovingPipe -> gapY q + moveAmp p * sin (phaseOf p q)
  _          -> gapY q

-- Current opening height for shrinking pipes.
pipeGapHeight :: Params -> Pipe -> Double
pipeGapHeight p q = case pipeKind q of
  ShrinkingPipe ->
    let s = (1 + sin (phaseOf p q)) / 2
        room = max 0 (pipeGap q - narrowMin p)
    in pipeGap q - s * room
  _ -> pipeGap q

-- False means no collision shapes for this pipe during its blink cycle.
pipeSolid :: Params -> Pipe -> Bool
pipeSolid p q
  | pipeBroken q = False
  | otherwise = case pipeKind q of
      VanishingPipe ->
        let period = max 0.001 (blinkPeriod p)
        in frac (realToFrac (pipeAge q) / period
                 + realToFrac (pipePhase q) / (2 * pi)) < blinkSolid p
      _ -> True

pipeShapes :: Params -> Pipe -> [Shape]
pipeShapes p q
  | not (pipeSolid p q) = []
  | otherwise =
      let c = pipeGapCenter p q
          h = pipeGapHeight p q
          xRaw = realToFrac (pipeX q)
          wRaw = realToFrac (pipeWidth q)
          -- Thu hẹp quanh tâm cột để khớp hình vẽ.
          w = wRaw * pipeHitScale
          x = xRaw + (wRaw - w) / 2
          screenHeightD = screenH p
          topHeight = max 0 (c - h / 2)
          lowerY = min screenHeightD (c + h / 2)
          lowerHeight = max 0 (screenHeightD - lowerY)
      in [ Rect x 0 w topHeight
         , Rect x lowerY w lowerHeight
         ]

-- Geometry for hazards. Inactive traps and wind zones do not collide here.
trapShape :: Params -> Trap -> Maybe Shape
trapShape p t
  | not (trapActive t) = Nothing
  | otherwise = case trapKind t of
      CeilingSpikes ->
          Just (Rect
              (realToFrac (trapX t) - hitW / 2)
              0
              hitW
              hitHeight)

      FloorSpikes ->
          Just (Rect
              (realToFrac (trapX t) - hitW / 2)
              (screenH p - hitHeight)
              hitW
              hitHeight)
      Fireball      -> Just (Circle (realToFrac (trapX t)) (realToFrac (trapY t)) (fireballRadius p * trapCircleHitScale))
      HunterBird    -> Just (Circle (realToFrac (trapX t)) (realToFrac (trapY t)) (hunterRadius p * trapCircleHitScale))
      StrongWind    -> Nothing
  where
    w = spikeWidth p
    h = spikeHeight p
    -- Trước đây hitHeight = h + 20 (rộng hơn hình). Giờ chỉ tính khi chạm ~nửa gai.
    hitHeight = h * spikeHitHeightScale
    hitW = w * spikeHitWidthScale

-- Giữ nguyên kích thước gốc để việc sinh/loại bẫy không bị ảnh hưởng.
trapExtent :: Params -> Double
trapExtent p = maximum
  [ spikeWidth p / 2
  , windWidth p / 2
  , fireballRadius p
  , hunterRadius p
  ]