
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
import System.Random (mkStdGen, randomR, randomRs)

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
    , gameItems = []
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

-- He so toc do.
-- Toc do chim khong tang theo diem.
-- Toc do cuon the gioi tang nhe moi 10 diem.
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
        { gameBird =
            flapBird
                (gameParams state)
                (gameModifiers state)
                (gameBird state)
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

        -- WorldDt dung cho chuyen dong the gioi.
        worldDt = dt * speedFactor (gameScore stateWithSkill)

        -- Vat ly chim giu he so toc do ban dau.
        birdDt = dt * baseSpeedBoost

        oldTraps = gameTraps stateWithSkill

        windMultiplier :: Float
        windMultiplier =
            if windCurseActive then 2 else 1

        movementModifiers = modifiers
            { speedMul =
                speedMul modifiers * realToFrac windMultiplier
            }

        scroll = PS.scrollSpeed stage movementModifiers

        trapsMoved =
            PS.updateTraps
                worldDt params movementModifiers stage oldTraps

        bird2 = updateBird birdDt params modifiers trapsMoved bird1
        bird3 = tickBirdSkill dt bird2

        oldPipes = gamePipes stateWithSkill

        (pipes2, trapsSpawned) =
            PS.updatePipes
                worldDt
                params
                movementModifiers
                stage
                (gameScore stateWithSkill)
                oldPipes

        traps2 = trapsMoved ++ trapsSpawned

        coinsMoved =
            moveCoinsWithSpeed
                worldDt scroll (gameCoins stateWithSkill)

        itemsMoved =
            moveItemsWithSpeed
                worldDt scroll (gameItems stateWithSkill)

        (coinsSpawned, itemsSpawned) =
            spawnCollectiblesFromRecycledPipes
                (pipeSpacingParam params)
                oldPipes
                pipes2
                coinsMoved
                itemsMoved

        -- Hut xu neu dang co hieu ung nam cham.
        magnetActive =
            any isMagnetEffect (gameEffects stateWithSkill)
                || (birdSkill bird3 == CoinMagnet
                    && birdSkillDuration bird3 > 0)

        coinsPulled =
            if magnetActive
                then pullCoins worldDt bird3 coinsSpawned
                else coinsSpawned

        ( coinsCollected
            , goldGained
            , diamondsGained
            , feathersGained
            , combo'
            ) =
            collectCoins
                bird3
                coinsPulled
                (gameCoinCombo stateWithSkill)

        (itemsCollected, pickedEffects) =
            collectItems bird3 itemsSpawned

        coins3 =
            filter
                (\c ->
                    not (coinCollected c)
                        && coinX c + coinRadius c > 0)
                coinsCollected

        items3 =
            filter
                (\i ->
                    not (itemCollected i)
                        && itemX i + itemRadius i > 0)
                itemsCollected

        effects2 =
            tickEffects dt (gameEffects stateWithSkill)
                ++ pickedEffects

        scoreGained = PS.scorePipes bird3 pipes2

        scoreMultiplier =
            if any isDoubleReward effects2
                then 2
                else 1

        score' =
            gameScore stateWithSkill
                + scoreGained * scoreMultiplier

        goldFinal =
            gameGold stateWithSkill
                + goldGained * scoreMultiplier

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

        shieldActive =
            any isShieldEffect effects2

        shieldWasActive =
            any isShieldEffect (gameEffects stateWithSkill)

        hitsPipe =
            hitsPipes params bird3 (gamePipes candidate)

        wasInsidePipe =
            hitsPipes params bird0 oldPipes

        -- Bat tu bo qua cot va bay,
        -- nhung van chet neu cham tran hoac dat.
        immortal = gameImmortal stateWithSkill

        collided =
            birdCollides
                params
                shieldActive
                immortal
                bird3
                (gamePipes candidate)
                (gameTraps candidate)

        candidate' =
            if collided
                then tryRevive candidate
                else candidate

        consumeShield =
            shieldActive
                && shieldWasActive
                && wasInsidePipe
                && not hitsPipe

        stillShieldActive =
            shieldActive && not consumeShield

        birdAfter = gameBird candidate'

        stillCollided =
            birdCollides
                params
                stillShieldActive
                immortal
                birdAfter
                (gamePipes candidate')
                (gameTraps candidate')

        status' =
            if stillCollided then GameOver else Playing

        withStatus =
            candidate' { gameStatus = status' }

        finalState =
            if consumeShield
                then withStatus
                    { gameEffects =
                        filter
                            (not . isShieldEffect)
                            (gameEffects withStatus)
                    }
                else withStatus

        analyzerInput = AnalyzerInput
            { aiStepBird =
                updateBird birdDt params modifiers []
            , aiScroll = scroll
            , aiWorldDt = worldDt
            , aiPipesPassed = scoreGained
            }

    in withDecision
        analyzerInput
        (updateBackgroundAndBoss dt finalState)

-- Hai nhanh phan tich danger va rage chay song song.
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

-- Keo xu ve phia chim.
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
    map
        (\coin ->
            coin { coinX = coinX coin - speed * dt })

-- ============================================================
-- SINH XU VA VAT PHAM
-- ============================================================

-- Moi lan cot duoc tai su dung, sinh toi da mot collectible.
-- Xac suat:
-- 60% xu vang
-- 15% khien
-- 5% WindCurse
-- 20% khong sinh
--
-- Vi tri Y co dao dong de vat pham khong xep thanh cum.

spawnCollectiblesFromRecycledPipes
    :: Float
    -> [Pipe]
    -> [Pipe]
    -> [Coin]
    -> [ItemPickup]
    -> ([Coin], [ItemPickup])

spawnCollectiblesFromRecycledPipes spacing oldPipes newPipes coins items =
    foldl
        spawn
        (coins, items)
        (zip3 [0 :: Int ..] oldPipes newPipes)
  where
    spawn (cs, its) (index, oldPipe, newPipe)
        | pipeX newPipe > pipeX oldPipe + spacing * 0.5 =
            let centerY =
                    (pipeGapTop newPipe + pipeGapBottom newPipe) / 2

                -- Tao seed theo lan tai su dung cot.
                seed =
                    round (pipeAge oldPipe * 1000)
                    + round (pipeX newPipe * 10)
                    + index * 104729

                gen0 = mkStdGen seed

                (roll, gen1) =
                    randomR (0 :: Int, 99) gen0

                (offsetY, _gen2) =
                    randomR (-30 :: Float, 30) gen1

                itemY =
                    max 70 (min 530 (centerY + offsetY))

                baseX =
                    pipeX newPipe + pipeWidth newPipe

                coin =
                    Coin
                        (baseX + 95)
                        itemY
                        9
                        GoldCoin
                        False

                shield =
                    ItemPickup
                        (baseX + 150)
                        itemY
                        13
                        Shield
                        False

                windCurse =
                    ItemPickup
                        (baseX + 150)
                        itemY
                        18
                        WindCurse
                        False

            in case roll of
                n | n < 60 ->
                    (coin : cs, its)

                  | n < 75 ->
                    (cs, shield : its)

                  | n < 80 ->
                    (cs, windCurse : its)

                  | otherwise ->
                    (cs, its)

    spawn acc _ = acc

-- ============================================================
-- DI CHUYEN VA THU THAP VAT PHAM
-- ============================================================

moveItemsWithSpeed :: Float -> Float -> [ItemPickup] -> [ItemPickup]
moveItemsWithSpeed dt speed =
    map
        (\item ->
            item { itemX = itemX item - speed * dt })

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
            (birdX bird)
            (birdY bird)
            (coinX coin)
            (coinY coin)
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
            (birdX bird)
            (birdY bird)
            (itemX item)
            (itemY item)
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

-- ============================================================
-- KY NANG
-- ============================================================

activateSkill :: Int -> GameState -> GameState
activateSkill slot state
    | slot /= 1 = state
    | birdSkill bird == NoSkill = state
    | gameRage state < rageMax = state
    | birdSkillDuration bird > 0 = state
    | otherwise = applySkill state
  where
    bird = gameBird state

    baseDuration =
        max 1
            (3 - fromIntegral (max 0 (birdLevel bird - 1)) * 0.1)

    bossRemaining =
        case gameBoss state of
            Just b | bossActive b -> bossTimeLeft b
            _                     -> 0

    duration =
        case birdSkill bird of
            Invisibility -> 3
            CoinMagnet -> 3 + bossRemaining
            _ -> baseDuration

    cooldown = 0

    applySkill s =
        let b = gameBird s

            b' = b
                { birdSkillCooldown = cooldown
                , birdSkillDuration = duration
                }

            effects' =
                case birdSkill b of
                    PassThroughPipe ->
                        PipePassEffect duration : gameEffects s

                    SlowTime ->
                        SlowEffect duration : gameEffects s

                    _ ->
                        gameEffects s

            pipes' =
                case birdSkill b of
                    DestroyNextPipe ->
                        PS.destroyNearestPipe
                            (birdX b)
                            (gamePipes s)

                    _ ->
                        gamePipes s

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
    | birdSkill bird == ReviveOnce
        && not (birdReviveUsed bird) =
            state
                { gameBird =
                    reviveBird (gameParams state) bird
                }

    | otherwise = state
  where
    bird = gameBird state

-- ============================================================
-- BOSS
-- GIU NGUYEN CO CHE PHUN CAU LUA
-- ============================================================

bossInterval :: Int
bossInterval = 10

-- Vong dau 5 giay, moi vong sau tang 3 giay.
bossDuration :: Int -> Float
bossDuration roundNo =
    5 + 3 * fromIntegral (max 0 (roundNo - 1))

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
    , bossFireCooldown = 0.8
    }

updateBackgroundAndBoss :: Float -> GameState -> GameState
updateBackgroundAndBoss dt state0 =
    let background =
            case stName (stageForScore (gameScore state0)) of
                "desert"  -> Desert
                "ice"     -> IceWorld
                "space"   -> SpaceWorld
                "volcano" -> Volcano
                _         -> Forest

        state =
            state0 { gameBackground = background }

    in if gameStatus state == GameOver
        then state
        else case gameBoss state of
            Nothing ->
                maybeStartBoss state

            Just boss
                | bossActive boss ->
                    updateBoss dt state boss

                | otherwise ->
                    state { gameBoss = Nothing }

-- Boss xuat hien tai cac moc 10, 20, 30... diem.
maybeStartBoss :: GameState -> GameState
maybeStartBoss state
    | score > 0
        && score `div` bossInterval
            > gameLastBossScore state `div` bossInterval =
        state
            { gameBoss =
                Just (newBoss (score `div` bossInterval))
            , gameLastBossScore = score
            , gamePipes = []
            , gameTraps = []
            , gameCoins = []
            , gameItems = []
            }

    | otherwise = state
  where
    score = gameScore state

-- Boss bay len xuong, dem gio va phun cau lua.
updateBoss :: Float -> GameState -> Boss -> GameState
updateBoss dt state boss
    | timeLeft' <= 0 =
        defeatBoss state

    | otherwise =
        state
            { gameBoss = Just boss'
            , gameTraps = gameTraps state ++ fireballs
            }
  where
    timeLeft' = bossTimeLeft boss - dt
    elapsed = bossTotalTime boss - timeLeft'

    y' =
        screenHeight / 2 + 180 * sin (elapsed * 2)

    cooldown0 =
        bossFireCooldown boss - dt

    (fireballs, cooldown')
        | cooldown0 <= 0 =
            ( bossVolley
                (gameParams state)
                (bossRound boss)
                (bossX boss)
                y'
                (round (timeLeft' * 1000))
            , bossFireInterval
            )

        | otherwise =
            ([], cooldown0)

    healthPct =
        max 0
            (min 100
                (round
                    (100 * timeLeft' / bossTotalTime boss)))

    boss' = boss
        { bossY = y'
        , bossTimeLeft = timeLeft'
        , bossHealth = healthPct
        , bossFireCooldown = cooldown'
        }

-- Mot dot cau lua tu boss.
bossVolley :: Params -> Int -> Float -> Float -> Int -> [Trap]
bossVolley params roundNo x bossY' seed =
    [ Trap (x - 50) y radius Fireball True
    | y <- bossY' : extraYs
    ]
  where
    count = min 4 (1 + roundNo)

    radius =
        realToFrac (fireballRadius params)

    gen =
        mkStdGen (seed * 7919 + roundNo * 104729)

    extraYs =
        take (count - 1)
            (randomRs (60, screenHeight - 60) gen)
            :: [Float]

-- Song sot het gio boss thi nhan 10 diem va 20 xu.
defeatBoss :: GameState -> GameState
defeatBoss state =
    state
        { gameBoss = Nothing
        , gameScore = gameScore state + 10

        , gameLastBossScore =
            gameScore state + 10

        , gameCoins = bossRewardCoins

        , gamePipes =
            PS.respawnPipes
                (gameParams state)
                (stageForScore (gameScore state))
                (gameScore state)

        , gameTraps = []
        }

-- 20 xu thuong sau khi danh bai boss.
bossRewardCoins :: [Coin]
bossRewardCoins =
    [ Coin
        (360 + fromIntegral col * 28)
        (220 + fromIntegral row * 36)
        9
        GoldCoin
        False
    | col <- [0 .. 4 :: Int]
    , row <- [0 .. 3 :: Int]
    ]
