module Physics
  ( -- * Chuyển động của chim
    updateBird
  , flapBird
  , reviveBird
  , tickBirdSkill
    -- * Gió
  , insideStrongWind
  , windAcceleration
    -- * Skill đang chạy
  , skillActive
    -- * Va chạm
  , hitsBoundary
  , hitsPipes
  , hitsTraps
  , birdCollides
  , checkCollision
  , checkCollisionWithParams
  , hitsShape
  , hitsShapes
  ) where

import GameState
import Geometry (Shape(..), pipeShapes, trapShape)

-- ===========================================================================
-- Chuyển động
-- ===========================================================================

-- | Cập nhật chuyển động của chim trong một bước thời gian.
--
-- QUY ƯỚC dt: 'dt' là số giây ĐÃ được nhân hệ số (timeScale, slow effect,
-- baseSpeedBoost...) ở nơi gọi (GameLoop). Hàm này KHÔNG nhân timeScale thêm
-- lần nữa.
--
-- Tọa độ y tăng từ trên xuống: gia tốc dương kéo chim xuống.
updateBird :: Float -> Params -> Modifiers -> [Trap] -> Bird -> Bird
updateBird dt params modifiers traps bird =
    bird
        { birdY = y'
        , birdVelocity = v'
        }
  where
    maxV = realToFrac (maxFallSpeed params)

    accel =
        realToFrac (gravity params) * realToFrac (gravityDir modifiers)
            + realToFrac (extraAccel modifiers)
            + windAcceleration params bird traps

    v' = max (negate maxV) (min maxV (birdVelocity bird + accel * dt))
    y' = birdY bird + v' * dt

-- | Vỗ cánh: đặt vận tốc về flapVelocity (đảo chiều nếu trọng lực đảo chiều).
flapBird :: Params -> Modifiers -> Bird -> Bird
flapBird params modifiers bird =
    bird
        { birdVelocity =
            realToFrac (flapVelocity params * gravityDir modifiers)
        }

-- | Đưa chim về giữa màn hình, vận tốc 0 và đánh dấu đã dùng hồi sinh.
-- GameLoop quyết định KHI NÀO được hồi sinh (xem tryRevive).
reviveBird :: Params -> Bird -> Bird
reviveBird params bird =
    bird
        { birdY = realToFrac (screenH params) / 2
        , birdVelocity = 0
        , birdReviveUsed = True
        }

-- | Trừ thời gian hồi chiêu / thời lượng skill của chim.
tickBirdSkill :: Float -> Bird -> Bird
tickBirdSkill dt bird =
    bird
        { birdSkillCooldown = max 0 (birdSkillCooldown bird - dt)
        , birdSkillDuration = max 0 (birdSkillDuration bird - dt)
        }

-- ===========================================================================
-- Gió
-- ===========================================================================

-- | Chim có đang nằm trong vùng gió mạnh này không.
insideStrongWind :: Params -> Bird -> Trap -> Bool
insideStrongWind params bird trap =
    trapActive trap
        && trapKind trap == StrongWind
        && abs (birdX bird - trapX trap)
            <= realToFrac (windWidth params) / 2

-- | Tổng gia tốc từ các vùng gió quanh chim. StrongWind là vùng lực (không có
-- hình va chạm), mặc định đẩy chim xuống (gia tốc dương).
windAcceleration :: Params -> Bird -> [Trap] -> Float
windAcceleration params bird traps =
    sum [ realToFrac (windStrength params)
        | trap <- traps
        , insideStrongWind params bird trap
        ]

-- ===========================================================================
-- Skill
-- ===========================================================================

-- | Chim có đúng skill này và skill đang chạy.
skillActive :: SkillType -> Bird -> Bool
skillActive skill bird =
    birdSkill bird == skill && birdSkillDuration bird > 0

-- ===========================================================================
-- Va chạm
-- ===========================================================================

hitsBoundary :: Params -> Bird -> Bool
hitsBoundary params bird =
    birdY bird - birdRadius bird <= 0
        || birdY bird + birdRadius bird >= realToFrac (screenH params)

hitsPipes :: Params -> Bird -> [Pipe] -> Bool
hitsPipes params bird = any (hitsShapes bird . pipeShapes params)

-- | Va chạm với bẫy. Hình học bẫy do Geometry cung cấp; vùng gió không có
-- hình va chạm. Dash / Invisibility miễn nhiễm mọi bẫy, FireTrapImmunity
-- chỉ miễn nhiễm cầu lửa.
hitsTraps :: Params -> Bird -> [Trap] -> Bool
hitsTraps params bird traps
    | skillActive Dash bird = False
    | skillActive Invisibility bird = False
    | otherwise = any collides traps
  where
    fireImmune = skillActive FireTrapImmunity bird

    collides trap
        | fireImmune && trapKind trap == Fireball = False
        | otherwise = maybe False (hitsShape bird) (trapShape params trap)

-- | Quy tắc chết tổng hợp (dùng cho cả lần kiểm tra trước và sau hồi sinh).
--
-- * Dash: bỏ qua MỌI va chạm (kể cả trần/đất).
-- * shielded: khiên bảo vệ khỏi cột.
-- * immortal: chế độ test, xuyên cột và bẫy; vẫn chết khi chạm trần/đất.
birdCollides :: Params -> Bool -> Bool -> Bird -> [Pipe] -> [Trap] -> Bool
birdCollides params shielded immortal bird pipes traps =
    not (skillActive Dash bird)
        && (  hitsBoundary params bird
           || (  not shielded
              && not (skillActive PassThroughPipe bird)
              && not immortal
              && hitsPipes params bird pipes )
           || (not immortal && hitsTraps params bird traps) )

-- | Bản đơn giản (không khiên, không bất tử, không bẫy) — giữ lại cho API cũ.
checkCollision :: Bird -> [Pipe] -> Bool
checkCollision = checkCollisionWithParams defaultParams

checkCollisionWithParams :: Params -> Bird -> [Pipe] -> Bool
checkCollisionWithParams params bird pipes =
    birdCollides params False False bird pipes []

-- | Va chạm hình tròn - hình chữ nhật / hình tròn - hình tròn.
hitsShapes :: Bird -> [Shape] -> Bool
hitsShapes bird = any (hitsShape bird)

hitsShape :: Bird -> Shape -> Bool
hitsShape bird (Rect x y w h) =
    let bx = realToFrac (birdX bird)
        by = realToFrac (birdY bird)
        r = realToFrac (birdRadius bird)
        closestX = max x (min bx (x + w))
        closestY = max y (min by (y + h))
        dx = bx - closestX
        dy = by - closestY
    in dx * dx + dy * dy <= r * r
hitsShape bird (Circle x y r) =
    let dx = realToFrac (birdX bird) - x
        dy = realToFrac (birdY bird) - y
        totalR = realToFrac (birdRadius bird) + r
    in dx * dx + dy * dy <= totalR * totalR