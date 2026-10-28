{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
module GameState where

import Control.DeepSeq (NFData)
import GHC.Generics (Generic)


-- Shared data model for the upgraded Flappy Bird project.
-- Coordinate convention: x increases to the right; y increases downward.

screenWidth, screenHeight :: Float
screenWidth = 800
screenHeight = 600

data Rarity = Common | Rare | Epic | Legendary
    deriving (Show, Eq, Ord, Enum, Bounded, Generic)

data BirdKind
    = Sparrow
    | Pigeon
    | Owl
    | Firebird
    | Eagle
    | IceBird
    | Phoenix
    | BabyDragon
    deriving (Show, Eq, Enum, Bounded, Generic)

data SkillType
    = NoSkill
    | PassThroughPipe       -- Owl: temporarily ignores pipe collision
    | Dash                  -- Eagle: short collision immunity / speed boost
    | SlowTime              -- Ice Bird: slows the world temporarily
    | ReviveOnce            -- Phoenix: revive once per run
    | DestroyNextPipe       -- Baby Dragon: destroy the nearest pipe
    | FireTrapImmunity      -- Firebird: ignores fire traps
    | Invisibility          -- Tàng hình 3s: bẫy / cầu lửa / gai không chạm được chim
    | CoinMagnet            -- Hút toàn bộ xu về phía chim (kể cả xu rơi sau khi hạ boss)
    deriving (Show, Eq, Enum, Bounded, Generic)

data Bird = Bird
    { birdX :: Float
    , birdY :: Float
    , birdVelocity :: Float
    , birdRadius :: Float
    , birdKind :: BirdKind
    , birdRarity :: Rarity
    , birdLevel :: Int                 -- expected range: 1..10
    , birdSkill :: SkillType
    , birdSkillCooldown :: Float       -- seconds remaining
    , birdSkillDuration :: Float       -- seconds remaining
    , birdReviveUsed :: Bool
    } deriving (Show, Eq, Generic)

data PipeKind = NormalPipe | MovingPipe | ShrinkingPipe | VanishingPipe
    deriving (Show, Eq, Enum, Bounded, Generic)

data Pipe = Pipe
    { pipeX :: Float
    , pipeGapTop :: Float
    , pipeGapBottom :: Float
    , pipeWidth :: Float
    , pipeScored :: Bool
    , pipeKind :: PipeKind
    , pipePhase :: Float               -- phase offset for animation
    , pipeAge :: Float                 -- seconds since this pipe spawned
    , pipeBroken :: Bool               -- destroyed pipes do not collide
    } deriving (Show, Eq, Generic)

data TrapKind = CeilingSpikes | FloorSpikes | Fireball | StrongWind | HunterBird
    deriving (Show, Eq, Enum, Bounded, Generic)

data Trap = Trap
    { trapX :: Float
    , trapY :: Float
    , trapRadius :: Float
    , trapKind :: TrapKind
    , trapActive :: Bool
    } deriving (Show, Eq, Generic)

data CurrencyKind = GoldCoin | Diamond | Feather
    deriving (Show, Eq, Enum, Bounded, Generic)

data Coin = Coin
    { coinX :: Float
    , coinY :: Float
    , coinRadius :: Float
    , coinKind :: CurrencyKind
    , coinCollected :: Bool
    } deriving (Show, Eq, Generic)

data ItemKind
    = Magnet
    | Shield
    | SlowItem
    | DoubleReward
    | Bomb
    | ExtraLife
    | WindCurse
    deriving (Show, Eq, Enum, Bounded, Generic)

data ItemPickup = ItemPickup
    { itemX :: Float
    , itemY :: Float
    , itemRadius :: Float
    , itemKind :: ItemKind
    , itemCollected :: Bool
    } deriving (Show, Eq, Generic)

data ActiveEffect
    = ShieldEffect Float
    | MagnetEffect Float
    | SlowEffect Float
    | DoubleRewardEffect Float
    | PipePassEffect Float
    | WindCurseEffect Float
    deriving (Show, Eq, Generic)

data Background = Forest | Desert | IceWorld | SpaceWorld | Volcano
    deriving (Show, Eq, Enum, Bounded, Generic)

data Boss = Boss
    { bossX :: Float
    , bossY :: Float
    , bossHealth :: Int                -- % thanh máu còn lại (100 -> 0)
    , bossActive :: Bool
    , bossRound :: Int                 -- vòng boss thứ mấy
    , bossTimeLeft :: Float            -- số giây còn lại phải sống sót
    , bossTotalTime :: Float           -- tổng số giây của màn boss này
    , bossFireCooldown :: Float        -- còn bao lâu nữa phun đợt lửa kế tiếp
    } deriving (Show, Eq, Generic)

-- ---------------------------------------------------------------------------
-- Kết quả của hai nhánh phân tích chạy song song (xem module Analyzer).
-- ---------------------------------------------------------------------------

data DangerLevel = Safe | Caution | Danger | Critical
    deriving (Show, Eq, Ord, Enum, Bounded, Generic, NFData)

-- Kết quả cuối cùng của Decision & Warning Engine, gửi thẳng cho frontend.
data Decision = Decision
    { decRage         :: Int          -- 0..100
    , decRageFull     :: Bool
    , decPipesToFull  :: Int          -- còn phải vượt bao nhiêu cột để đầy nộ
    , decSkillReady   :: Bool         -- nộ đầy + chim có skill + skill chưa chạy
    , decSkillActive  :: Bool         -- skill đang chạy
    , decSkillTimeLeft :: Float       -- giây còn lại của skill đang chạy
    , decDangerLevel  :: DangerLevel
    , decTimeToHit    :: Float        -- giây dự đoán sẽ va chạm, -1 nếu không có
    , decNearestDistance :: Float     -- px tới vật cản gần nhất phía trước, -1 nếu không có
    , decThreat       :: String       -- "pipe" | "trap" | "boundary" | ""
    , decWarningRed   :: Bool         -- frontend bật cảnh báo đỏ
    , decSuggestSkill :: Bool         -- nguy hiểm + skill sẵn sàng => gợi ý bấm skill
    } deriving (Show, Eq, Generic, NFData)

defaultDecision :: Decision
defaultDecision = Decision
    { decRage = 0
    , decRageFull = False
    , decPipesToFull = 5
    , decSkillReady = False
    , decSkillActive = False
    , decSkillTimeLeft = 0
    , decDangerLevel = Safe
    , decTimeToHit = -1
    , decNearestDistance = -1
    , decThreat = ""
    , decWarningRed = False
    , decSuggestSkill = False
    }

data GameStatus = Ready | Playing | GameOver
    deriving (Show, Eq, Generic)

data Input
    = NoInput
    | Flap
    | Start
    | Restart
    | UseSkill Int
    deriving (Show, Eq, Generic)

-- Các thông số cấu hình của game
data Params = Params
  { gravity        :: Double
  , flapVelocity   :: Double
  , maxFallSpeed   :: Double
  , pipeWidthParam :: Double
  , gapSize        :: Double
  , pipeSpacing    :: Double
  , screenW        :: Double
  , screenH        :: Double
  , gapMargin      :: Double
  , maxGapShift    :: Double
  , birdFixedX     :: Double
  , birdRadiusParam :: Double
  , moveAmp        :: Double
  , movePeriod     :: Double
  , narrowMin      :: Double
  , blinkPeriod    :: Double
  , blinkSolid     :: Double
  , spikeHeight    :: Double
  , spikeWidth     :: Double
  , fireballSpeed  :: Double
  , fireballRadius :: Double
  , windStrength   :: Double
  , windWidth      :: Double
  , hunterSpeed    :: Double
  , hunterRadius   :: Double
  , hunterChase    :: Double
  , hunterLifetime :: Double
  } deriving (Show, Eq, Generic)

-- Các thông số điều chỉnh tạm thời
data Modifiers = Modifiers
  { timeScale    :: Double
  , speedMul     :: Double
  , extraAccel   :: Double
  , gravityDir   :: Double
  , spawnEnabled :: Bool
  } deriving (Show, Eq, Generic)

-- Cấu hình mặc định
defaultParams :: Params
defaultParams = Params
  { gravity        = 1500
  , flapVelocity   = -450
  , maxFallSpeed   = 700
  , pipeWidthParam = 60
  , gapSize        = 160
  , pipeSpacing    = 220
  , screenW        = 800
  , screenH        = 600
  , gapMargin      = 60
  , maxGapShift    = 110
  , birdFixedX     = 150
  , birdRadiusParam = 15
  , moveAmp        = 40
  , movePeriod     = 3
  , narrowMin      = 90
  , blinkPeriod    = 2
  , blinkSolid     = 0.6
  , spikeHeight    = 180
  , spikeWidth     = 70
  , fireballSpeed  = 60
  , fireballRadius = 18
  , windStrength   = 400
  , windWidth      = 100
  , hunterSpeed    = 40
  , hunterRadius   = 16
  , hunterChase    = 80
  , hunterLifetime = 3
  }

defaultModifiers :: Modifiers
defaultModifiers = Modifiers
  { timeScale    = 1
  , speedMul     = 1
  , extraAccel   = 0
  , gravityDir   = 1
  , spawnEnabled = True
  }

data GameState = GameState
    { gameBird :: Bird
    , gamePipes :: [Pipe]
    , gameTraps :: [Trap]
    , gameCoins :: [Coin]
    , gameItems :: [ItemPickup]
    , gameEffects :: [ActiveEffect]
    , gameParams :: Params
    , gameModifiers :: Modifiers
    , gameScore :: Int
    , gameGold :: Int
    , gameDiamonds :: Int
    , gameFeathers :: Int
    , gameCoinCombo :: Int
    , gameStatus :: GameStatus
    , gameBackground :: Background
    , gameBoss :: Maybe Boss
    , gameLastBossScore :: Int
    , gameWindBoostTime :: Float
    , gameInsideStrongWind :: Bool
    , gameRage :: Int                  -- thanh nộ 0..100 (+20 mỗi cột vượt qua)
    , gameDecision :: Decision         -- kết quả phân tích của frame gần nhất
    , gameImmortal :: Bool             -- chế độ bất tử (test): xuyên cột, vẫn chết khi chạm trần/đất
    } deriving (Show, Eq, Generic)

-- The default bird is a common sparrow without an active skill.
defaultBird :: Bird
defaultBird = Bird
    { birdX = 150
    , birdY = 300
    , birdVelocity = 0
    , birdRadius = 15
    , birdKind = Sparrow
    , birdRarity = Common
    , birdLevel = 1
    , birdSkill = NoSkill
    , birdSkillCooldown = 0
    , birdSkillDuration = 0
    , birdReviveUsed = False
    }

-- ---------------------------------------------------------------------------
-- Skill theo loại chim. Chim thường (Sparrow) không có skill.
-- ---------------------------------------------------------------------------
skillForBird :: BirdKind -> SkillType
skillForBird Sparrow  = NoSkill
skillForBird Firebird = Invisibility   -- skin "neon"
skillForBird Owl      = CoinMagnet     -- skin "cyber"
skillForBird _        = NoSkill

-- Tạo chim đúng loại kèm skill tương ứng.
birdWithKind :: BirdKind -> Bird
birdWithKind kind = defaultBird
    { birdKind = kind
    , birdSkill = skillForBird kind
    }


--   classic -> Sparrow (không skill), neon -> Firebird (tàng hình 3s),
--   cyber   -> Owl (nam châm hút xu)
birdForSkin :: String -> Bird
birdForSkin "neon"  = birdWithKind Firebird
birdForSkin "cyber" = birdWithKind Owl
birdForSkin _       = birdWithKind Sparrow