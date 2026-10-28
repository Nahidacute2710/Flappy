module GameLoop
    ( timeStep
    , gravity
    , flapVelocity
    , pipeSpeed
    , pipeSpacing
    , initialGameState
    , stepGame
    , checkCollision
    , activateSkill
    , newBoss
    ) where

import GameState hiding (gravity, flapVelocity, pipeSpacing)
import qualified GameState as GS
import Physics
import qualified PipeSystem as PS
import Analyzer
import Stage (Stage(..), stageForScore)
import System.Random (mkStdGen, randomRs)

-- Game update rate: 60 updates per second.
timeStep :: Float
timeStep = 1 / 60

-- Legacy constants retained for compatibility with other modules.
-- The actual gameplay uses values stored in gameParams.
gravity, flapVelocity, pipeSpeed, pipeSpacing :: Float
gravity = realToFrac (GS.gravity defaultParams)
flapVelocity = realToFrac (GS.flapVelocity defaultParams)
pipeSpeed = 180
pipeSpacing = realToFrac (GS.pipeSpacing defaultParams)

-- Initial state of the game.
initialGameState :: GameState
initialGameState = GameState
    { gameBird = defaultBird
    , gamePipes = PS.initialPipes
    , gameTraps = PS.initialTraps PS.initialPipes
    , gameCoins = []
    , gameItems =
        [ ItemPickup 520 280 18 WindCurse False
        ]
    , gameEffects = []
    , gameParams = defaultParams
    , gameModifiers = defaultModifiers
    , gameScore = 0
    , gameGold = 0
    , gameDiamonds = 0
    , gameFeathers = 0
    , gameCoinCombo = 0
    , gameStatus = Ready
    , gameBackground = Forest
    , gameBoss = Nothing
    , gameLastBossScore = 0
    , gameWindBoostTime = 0
    , gameInsideStrongWind = False
    , gameRage = 0
    , gameDecision = defaultDecision
    , gameImmortal = False
    }

-- | Hệ số tốc độ.
--
-- * baseSpeedBoost: hệ số lúc mới vào game (1.5), cũng là hệ số vật lý của CHIM
--   (trọng lực, lực vỗ cánh, tốc độ rơi) và giữ NGUYÊN ở mọi vòng, để chim
--   luôn rơi/bay đúng cảm giác lúc mới bắt đầu.
-- * speedFactor: chỉ dùng cho tốc độ cuộn của thế giới (cột, bẫy, xu, vật phẩm).
--   Mỗi 10 điểm nhân thêm speedStepRatio, nhưng không vượt maxSpeedFactor.
--   Lưu ý stage (Stage.hs) cũng đã tăng stSpeed theo mốc điểm, nên hệ số này
--   cố ý tăng nhẹ để hai lớp tăng tốc không cộng dồn thành quá nhanh.
--
-- Chỉnh độ khó ở đây: speedStepRatio (mỗi vòng nhanh thêm bao nhiêu) và
-- maxSpeedFactor (trần tốc độ cuộn).
baseSpeedBoost, speedStepRatio, maxSpeedFactor :: Float
baseSpeedBoost = 1.5
speedStepRatio = 1.05
maxSpeedFactor = 2.2

speedFactor :: Int -> Float
speedFactor score =
    min maxSpeedFactor
        (baseSpeedBoost * speedStepRatio ^ (max 0 score `div` 10))

stepGame :: Input -> GameState -> GameState
stepGame input state
    | input == Restart =
        initialGameState
            { gameBird = birdWithKind (birdKind (gameBird state))
            , gameImmortal = gameImmortal state
            }
    | otherwise =
        case gameStatus state of
            Ready ->
                case input of
                    Start -> state { gameStatus = Playing }
                    Flap  -> startAndFlap state
                    _     -> state

            Playing -> updatePlaying input state
            GameOver -> state

startAndFlap :: GameState -> GameState
startAndFlap state =
    state
        { gameBird = flapBird (gameParams state) (gameModifiers state) (gameBird state)
        , gameStatus = Playing
        }

pipeSpacingParam :: Params -> Float
pipeSpacingParam = realToFrac . GS.pipeSpacing

updatePlaying :: Input -> GameState -> GameState
updatePlaying input state =
    let stateWithSkill =
            case input of
                UseSkill slot -> activateSkill slot state
                _             -> state

        params = gameParams stateWithSkill
        modifiers = gameModifiers stateWithSkill
        stage = stageForScore (gameScore stateWithSkill)

        bird0 = gameBird stateWithSkill

        bird1 =
            case input of
                Flap -> flapBird params modifiers bird0
                _    -> bird0

        slowed = any isSlowEffect (gameEffects stateWithSkill)
        windCurseActive =
                    any isWindCurseEffect (gameEffects stateWithSkill)
        
        baseDt = timeStep * realToFrac (timeScale modifiers)
        dt = if slowed then baseDt * 0.5 else baseDt

        -- dt thật dùng cho hồi chiêu/hiệu ứng; worldDt dùng cho chuyển động.
        worldDt = dt * speedFactor (gameScore stateWithSkill)

        -- Vật lý của chim luôn dùng hệ số lúc mới start, không tăng theo vòng.
        birdDt = dt * baseSpeedBoost

        oldTraps = gameTraps stateWithSkill

        -- Chỉ tăng tốc khi hiệu ứng WindCurse còn hiệu lực.
        windMultiplier :: Float
        windMultiplier =
            if windCurseActive then 2 else 1

        movementModifiers = modifiers
            { speedMul =
                speedMul modifiers * realToFrac windMultiplier
            }

        -- Tốc độ cuộn thế giới (đã gồm WindCurse), dùng chung cho mọi vật thể.
        scroll = PS.scrollSpeed stage movementModifiers

        trapsMoved =
            PS.updateTraps worldDt params movementModifiers stage oldTraps

        -- Vật lý chim (trọng lực, gió, giới hạn tốc độ) nằm trong Physics.
        bird2 = updateBird birdDt params modifiers trapsMoved bird1
        bird3 = tickBirdSkill dt bird2

        oldPipes = gamePipes stateWithSkill

        (pipes2, trapsSpawned) =
            PS.updatePipes worldDt params movementModifiers stage
                (gameScore stateWithSkill) oldPipes

        traps2 = trapsMoved ++ trapsSpawned

        coinsMoved =
            moveCoinsWithSpeed worldDt scroll (gameCoins stateWithSkill)

        itemsMoved =
            moveItemsWithSpeed worldDt scroll (gameItems stateWithSkill)

        (coinsSpawned, itemsSpawned) =
            spawnCollectiblesFromRecycledPipes
                (pipeSpacingParam params)
                oldPipes
                pipes2
                coinsMoved
                itemsMoved

        -- Hút xu: skill CoinMagnet hoặc vật phẩm Magnet đang hiệu lực.
        magnetActive =
            any isMagnetEffect (gameEffects stateWithSkill)
                || (birdSkill bird3 == CoinMagnet
                    && birdSkillDuration bird3 > 0)

        coinsPulled =
            if magnetActive
                then pullCoins worldDt bird3 coinsSpawned
                else coinsSpawned

        (coinsCollected, goldGained, diamondsGained,
            feathersGained, combo') =
            collectCoins bird3 coinsPulled
                (gameCoinCombo stateWithSkill)

        (itemsCollected, pickedEffects) =
            collectItems bird3 itemsSpawned

        coins3 =
            filter
                (\c -> not (coinCollected c) && coinX c + coinRadius c > 0)
                coinsCollected

        items3 =
            filter
                (\i -> not (itemCollected i) && itemX i + itemRadius i > 0)
                itemsCollected

        -- Existing effects lose time; newly collected effects are added.
        effects2 =
            tickEffects dt (gameEffects stateWithSkill)
                ++ pickedEffects

        scoreGained = PS.scorePipes bird3 pipes2

        scoreMultiplier =
            if any isDoubleReward effects2
                then 2
                else 1

        score' =
            gameScore stateWithSkill + scoreGained * scoreMultiplier

        goldFinal =
            gameGold stateWithSkill + goldGained * scoreMultiplier

        diamondsFinal =
            gameDiamonds stateWithSkill + diamondsGained

        feathersFinal =
            gameFeathers stateWithSkill + feathersGained

        candidate = stateWithSkill
            { gameBird = bird3
            , gamePipes = PS.markScored bird3 pipes2
            , gameTraps = traps2
            , gameCoins = coins3
            , gameItems = items3
            , gameEffects = effects2
            , gameScore = score'
            , gameGold = goldFinal
            , gameDiamonds = diamondsFinal
            , gameFeathers = feathersFinal
            , gameCoinCombo = combo'
            }

        -- Khiên chỉ có hiệu lực nếu vẫn còn trong effects2.
        -- effects2 đã trừ thời gian của khiên cũ và giữ khiên vừa nhặt.
        shieldActive =
            any isShieldEffect effects2

        shieldWasActive =
            any isShieldEffect (gameEffects stateWithSkill)

        hitsPipe =
            hitsPipes params bird3 (gamePipes candidate)

        wasInsidePipe =
            hitsPipes params bird0 oldPipes

        -- Chế độ bất tử: bỏ qua cột và mọi bẫy (kể cả cầu lửa của boss);
        -- chỉ chạm trần hoặc đất mới chết. Quy tắc chết nằm ở Physics.birdCollides.
        immortal = gameImmortal stateWithSkill

        collided =
            birdCollides params shieldActive immortal bird3
                (gamePipes candidate) (gameTraps candidate)

        candidate' =
            if collided
                then tryRevive candidate
                else candidate


        -- Khiên chỉ bị tiêu thụ sau khi chim đi qua hoàn toàn một cột.
        consumeShield =
            shieldActive
                && shieldWasActive
                && wasInsidePipe
                && not hitsPipe

        -- Sau khi tiêu thụ khiên, cột tiếp theo sẽ gây va chạm bình thường.
        stillShieldActive =
            shieldActive && not consumeShield

        birdAfter = gameBird candidate'

        stillCollided =
            birdCollides params stillShieldActive immortal birdAfter
                (gamePipes candidate') (gameTraps candidate')

        status' =
            if stillCollided then GameOver else Playing

        withStatus =
            candidate' { gameStatus = status' }

        -- Chỉ xóa khiên một lần, sau khi đã qua hết cột.
        finalState =
            if consumeShield
                then withStatus
                    { gameEffects =
                        filter
                            (not . isShieldEffect)
                            (gameEffects withStatus)
                    }
                else withStatus

        -- Đầu vào cho hai nhánh phân tích song song (Analyzer).
        analyzerInput = AnalyzerInput
            { aiStepBird =
                updateBird birdDt params modifiers []
            , aiScroll = scroll
            , aiWorldDt = worldDt
            , aiPipesPassed = scoreGained
            }

    in withDecision analyzerInput (updateBackgroundAndBoss dt finalState)

-- | Chạy Danger Analyzer + Rage & Skill Engine song song, rồi ghi kết quả
-- (thanh nộ + cảnh báo + trạng thái skill) vào GameState để gửi qua JSON API.
withDecision :: AnalyzerInput -> GameState -> GameState
withDecision ai state
    | gameStatus state == GameOver = state
    | otherwise =
        let decision = analyzeParallel ai state
        in state
            { gameRage = decRage decision
            , gameDecision = decision
            }

isMagnetEffect :: ActiveEffect -> Bool
isMagnetEffect (MagnetEffect t) = t > 0
isMagnetEffect _ = False

-- | Kéo mọi xu trên màn hình về phía chim.
pullCoins :: Float -> Bird -> [Coin] -> [Coin]
pullCoins dt bird = map pull
  where
    pullSpeed = 700
    pull coin
        | coinCollected coin = coin
        | dist < 0.001 = coin
        | otherwise =
            coin
                { coinX = coinX coin + dx / dist * step
                , coinY = coinY coin + dy / dist * step
                }
      where
        dx = birdX bird - coinX coin
        dy = birdY bird - coinY coin
        dist = sqrt (dx * dx + dy * dy)
        step = min dist (pullSpeed * dt)

isWindCurseEffect :: ActiveEffect -> Bool
isWindCurseEffect (WindCurseEffect t) = t > 0
isWindCurseEffect _ = False


moveCoinsWithSpeed :: Float -> Float -> [Coin] -> [Coin]
moveCoinsWithSpeed dt speed =
    map (\coin -> coin { coinX = coinX coin - speed * dt })

spawnCollectiblesFromRecycledPipes
    :: Float
    -> [Pipe]
    -> [Pipe]
    -> [Coin]
    -> [ItemPickup]
    -> ([Coin], [ItemPickup])
spawnCollectiblesFromRecycledPipes spacing oldPipes newPipes coins items =
    foldl spawn (coins, items) (zip3 [0 :: Int ..] oldPipes newPipes)
  where
    spawn (cs, its) (_, oldPipe, newPipe)
        | pipeX newPipe > pipeX oldPipe + spacing * 0.5 =
            let centerY =
                    (pipeGapTop newPipe + pipeGapBottom newPipe) / 2

                coin =
                    Coin
                        (pipeX newPipe + pipeWidth newPipe + 60)
                        (centerY - 25)
                        9
                        GoldCoin
                        False

                shield =
                    ItemPickup
                        (pipeX newPipe + pipeWidth newPipe + 120)
                        (centerY + 25)
                        13
                        Shield
                        False

                windCurse =
                    ItemPickup
                        (pipeX newPipe + pipeWidth newPipe + 180)
                        (centerY + 70)
                        18
                        WindCurse
                        False

                newItems = windCurse : shield : its

            in (coin : cs, newItems)

    -- Pipe chưa được tái sử dụng thì giữ nguyên collectibles.
    spawn acc _ = acc
    
moveItemsWithSpeed :: Float -> Float -> [ItemPickup] -> [ItemPickup]
moveItemsWithSpeed dt speed =
    map (\item -> item { itemX = itemX item - speed * dt })

collectCoins :: Bird -> [Coin] -> Int -> ([Coin], Int, Int, Int, Int)
collectCoins bird coins oldCombo =
    let (coins', gold, diamonds, feathers, collectedCount) =
            foldr collectOne ([], 0, 0, 0, 0) coins

        combo' =
            if collectedCount > 0
                then oldCombo + collectedCount
                else 0

    in (coins', gold, diamonds, feathers, combo')
  where
    collectOne coin (rest, gold, diamonds, feathers, count)
        | coinCollected coin =
            (coin : rest, gold, diamonds, feathers, count)

        | distanceSquared
            (birdX bird) (birdY bird)
            (coinX coin) (coinY coin)
            <= (birdRadius bird + coinRadius coin) ^ (2 :: Int) =
                ( coin { coinCollected = True } : rest
                , gold + if coinKind coin == GoldCoin then 1 else 0
                , diamonds + if coinKind coin == Diamond then 1 else 0
                , feathers + if coinKind coin == Feather then 1 else 0
                , count + 1
                )

        | otherwise =
            (coin : rest, gold, diamonds, feathers, count)

collectItems
    :: Bird
    -> [ItemPickup]
    -> ([ItemPickup], [ActiveEffect])
collectItems bird items =
    foldr collectOne ([], []) items
  where
    collectOne item (rest, effects)
        | itemCollected item =
            (rest, effects)

        | distanceSquared
            (birdX bird) (birdY bird)
            (itemX item) (itemY item)
            <= (birdRadius bird + itemRadius item) ^ (2 :: Int) =
                (rest, effectFor (itemKind item) ++ effects)

        | otherwise =
            (item : rest, effects)

    effectFor Shield =
        [ShieldEffect 5]

    effectFor Magnet =
        [MagnetEffect 5]

    effectFor SlowItem =
        [SlowEffect 4]

    effectFor DoubleReward =
        [DoubleRewardEffect 5]
    
    effectFor WindCurse =
        [WindCurseEffect 2]
    
    effectFor Bomb = []
    effectFor ExtraLife = []

distanceSquared :: Float -> Float -> Float -> Float -> Float
distanceSquared x1 y1 x2 y2 =
    (x1 - x2) ^ 2 + (y1 - y2) ^ 2

activateSkill :: Int -> GameState -> GameState
activateSkill slot state
    | slot /= 1 = state
    | birdSkill bird == NoSkill = state
    | gameRage state < rageMax = state          -- phải đầy nộ mới dùng được
    | birdSkillDuration bird > 0 = state        -- skill đang chạy
    | otherwise = applySkill state
  where
    bird = gameBird state

    baseDuration =
        max 1
            (3 - fromIntegral (max 0 (birdLevel bird - 1)) * 0.1)

    -- Số giây còn lại của màn boss đang diễn ra (0 nếu không có boss).
    bossRemaining =
        case gameBoss state of
            Just b | bossActive b -> bossTimeLeft b
            _                     -> 0

    duration =
        case birdSkill bird of
            Invisibility -> 3
            -- Dùng trong lúc đánh boss thì nam châm giữ nguyên tới khi boss
            -- chết, rồi hút thêm 3 giây số xu rơi ra.
            CoinMagnet   -> 3 + bossRemaining
            _            -> baseDuration

    -- Nộ thay thế cooldown: dùng xong nộ về 0 và phải vượt 5 cột để đầy lại.
    cooldown = 0

    applySkill s =
        let b = gameBird s

            b' = b
                { birdSkillCooldown = cooldown
                , birdSkillDuration = duration
                }

            effects' =
                case birdSkill b of
                    PassThroughPipe -> PipePassEffect duration : gameEffects s
                    SlowTime        -> SlowEffect duration : gameEffects s
                    _               -> gameEffects s

            pipes' =
                case birdSkill b of
                    DestroyNextPipe -> PS.destroyNearestPipe
                        (birdX b) (gamePipes s)
                    _ -> gamePipes s

        in s
            { gameBird = b'
            , gameEffects = effects'
            , gamePipes = pipes'
            , gameRage = 0
            }

tickEffects :: Float -> [ActiveEffect] -> [ActiveEffect]
tickEffects dt = foldr tick []
  where
    tick effect rest =
        case effect of
            ShieldEffect t | t > dt ->
                ShieldEffect (t - dt) : rest

            MagnetEffect t | t > dt ->
                MagnetEffect (t - dt) : rest

            SlowEffect t | t > dt ->
                SlowEffect (t - dt) : rest

            DoubleRewardEffect t | t > dt ->
                DoubleRewardEffect (t - dt) : rest

            PipePassEffect t | t > dt ->
                PipePassEffect (t - dt) : rest
            
            WindCurseEffect t | t > dt ->
                WindCurseEffect (t - dt) : rest

            _ -> rest

isSlowEffect :: ActiveEffect -> Bool
isSlowEffect (SlowEffect _) = True
isSlowEffect _ = False

isDoubleReward :: ActiveEffect -> Bool
isDoubleReward (DoubleRewardEffect _) = True
isDoubleReward _ = False

isShieldEffect :: ActiveEffect -> Bool
isShieldEffect (ShieldEffect t) = t > 0
isShieldEffect _ = False


tryRevive :: GameState -> GameState
tryRevive state
    | birdSkill bird == ReviveOnce && not (birdReviveUsed bird) =
        state { gameBird = reviveBird (gameParams state) bird }
    | otherwise = state
  where
    bird = gameBird state

-- ===========================================================================
-- BOSS
-- ===========================================================================

bossInterval :: Int
bossInterval = 10

-- | Vòng 1 = 5 giây, mỗi vòng sau cộng thêm 3 giây.
bossDuration :: Int -> Float
bossDuration roundNo = 5 + 3 * fromIntegral (max 0 (roundNo - 1))

bossFireInterval :: Float
bossFireInterval = 1.0

newBoss :: Int -> Boss
newBoss roundNo = Boss
    { bossX = screenWidth - 100
    , bossY = screenHeight / 2
    , bossHealth = 100
    , bossActive = True
    , bossRound = roundNo
    , bossTimeLeft = bossDuration roundNo
    , bossTotalTime = bossDuration roundNo
    , bossFireCooldown = 0.8          -- cho người chơi ~0.8s chuẩn bị
    }

updateBackgroundAndBoss :: Float -> GameState -> GameState
updateBackgroundAndBoss dt state0 =
    let background = case stName (stageForScore (gameScore state0)) of
            "desert"  -> Desert
            "ice"     -> IceWorld
            "space"   -> SpaceWorld
            "volcano" -> Volcano
            _         -> Forest

        state = state0 { gameBackground = background }
    in if gameStatus state == GameOver
        then state
        else case gameBoss state of
            Nothing -> maybeStartBoss state
            Just boss
                | bossActive boss -> updateBoss dt state boss
                | otherwise       -> state { gameBoss = Nothing }

-- | Qua mốc 10, 20, 30... điểm thì dọn sân và gọi boss ra.
maybeStartBoss :: GameState -> GameState
maybeStartBoss state
    | score > 0
        && score `div` bossInterval
            > gameLastBossScore state `div` bossInterval =
        state
            { gameBoss = Just (newBoss (score `div` bossInterval))
            , gameLastBossScore = score
            , gamePipes = []
            , gameTraps = []
            , gameCoins = []
            , gameItems = []
            }
    | otherwise = state
  where
    score = gameScore state

-- | Mỗi tick: boss bay lên xuống, đếm ngược, phun lửa; hết giờ thì chết.
updateBoss :: Float -> GameState -> Boss -> GameState
updateBoss dt state boss
    | timeLeft' <= 0 = defeatBoss state
    | otherwise =
        state
            { gameBoss = Just boss'
            , gameTraps = gameTraps state ++ fireballs
            }
  where
    timeLeft' = bossTimeLeft boss - dt
    elapsed   = bossTotalTime boss - timeLeft'

    y' = screenHeight / 2 + 180 * sin (elapsed * 2)

    cooldown0 = bossFireCooldown boss - dt

    (fireballs, cooldown')
        | cooldown0 <= 0 =
            ( bossVolley (gameParams state) (bossRound boss)
                (bossX boss) y' (round (timeLeft' * 1000))
            , bossFireInterval )
        | otherwise = ([], cooldown0)

    healthPct = max 0 (min 100
        (round (100 * timeLeft' / bossTotalTime boss)))

    boss' = boss
        { bossY = y'
        , bossTimeLeft = timeLeft'
        , bossHealth = healthPct
        , bossFireCooldown = cooldown'
        }

-- | Một đợt lửa: 1 quả từ vị trí boss + vài quả ở độ cao ngẫu nhiên (tối đa 4).
bossVolley :: Params -> Int -> Float -> Float -> Int -> [Trap]
bossVolley params roundNo x bossY' seed =
    [ Trap (x - 50) y radius Fireball True | y <- bossY' : extraYs ]
  where
    count   = min 4 (1 + roundNo)
    radius  = realToFrac (fireballRadius params)
    gen     = mkStdGen (seed * 7919 + roundNo * 104729)
    extraYs = take (count - 1)
                (randomRs (60, screenHeight - 60) gen) :: [Float]

-- | Sống sót đủ thời gian thì hạ boss, cộng 10 điểm và nhận 20 xu.
defeatBoss :: GameState -> GameState
defeatBoss state =
    state
        { gameBoss = Nothing
        , gameScore = gameScore state + 10
        -- Cập nhật mốc boss, nếu không điểm +10 sẽ gọi boss kế tiếp ngay
        -- và xóa sạch 20 xu thưởng.
        , gameLastBossScore = gameScore state + 10
        , gameCoins = bossRewardCoins
        , gamePipes =
            PS.respawnPipes
                (gameParams state)
                (stageForScore (gameScore state))
                (gameScore state)
        , gameTraps = []
        }

-- | 20 xu vàng xếp lưới 5 cột x 4 hàng, nằm trước cột đầu tiên.
bossRewardCoins :: [Coin]
bossRewardCoins =
    [ Coin (360 + fromIntegral col * 28)
           (220 + fromIntegral row * 36)
           9 GoldCoin False
    | col <- [0 .. 4 :: Int]
    , row <- [0 .. 3 :: Int]
    ]