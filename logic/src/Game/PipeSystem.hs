
module PipeSystem
  ( pipeCount
  , loGap, hiGap
  , mkPipe
  , nextGap
  , pickWeighted
  , spawnPipe
  , spawnTrap
  , initialPipes
  , initialTraps
  , scrollSpeed
  , updatePipes
  , updateTraps
  , respawnPipes
  , scorePipes
  , markScored
  , destroyNearestPipe
  , breakPipeAhead
  , clearTraps
  ) where

import Data.List (maximumBy)
import Data.Maybe (maybeToList)
import Data.Ord (comparing)
import System.Random (StdGen, mkStdGen, randomR)

import GameState
import Geometry (trapExtent)
import Stage

-- ============================================================
-- Sinh cot va bay
-- ============================================================

pipeCount :: Params -> Int
pipeCount p =
  ceiling ((screenW p + pipeWidthParam p) / pipeSpacing p) + 1

loGap, hiGap :: Params -> Double
loGap p =
  gapMargin p + gapSize p / 2 + moveAmp p

hiGap p =
  screenH p - gapMargin p - gapSize p / 2 - moveAmp p

-- Tao cot theo cau truc Pipe.
mkPipe :: Params -> Double -> Double -> PipeKind -> Double -> Double -> Pipe
mkPipe p x center kind gap phase = Pipe
  { pipeX = realToFrac x
  , pipeGapTop = realToFrac (center - gap / 2)
  , pipeGapBottom = realToFrac (center + gap / 2)
  , pipeWidth = realToFrac (pipeWidthParam p)
  , pipeScored = False
  , pipeKind = kind
  , pipePhase = realToFrac phase
  , pipeAge = 0
  , pipeBroken = False
  }

nextGap :: Params -> StdGen -> Double -> (Double, StdGen)
nextGap p gen previous =
  let lower = max (loGap p) (previous - maxGapShift p)
      upper = min (hiGap p) (previous + maxGapShift p)
  in randomR (min lower upper, max lower upper) gen

-- Chon ngau nhien theo trong so.
pickWeighted :: [(a, Int)] -> StdGen -> (a, StdGen)
pickWeighted weighted gen =
  let valid = filter ((> 0) . snd) weighted
      total = sum (map snd valid)
  in if total <= 0
       then error "pickWeighted: can it nhat mot trong so duong"
       else
         let (roll, gen') = randomR (1, total) gen
         in (choose roll valid, gen')
  where
    choose _ [] =
      error "pickWeighted: danh sach trong so rong"

    choose roll ((value, weight):rest)
      | roll <= weight = value
      | otherwise = choose (roll - weight) rest

spawnPipe :: Params -> Stage -> StdGen -> Double -> Maybe Double -> (Pipe, StdGen)
spawnPipe p stage gen x previousGap =
  let (kind, g1) = pickWeighted (stPipeWeights stage) gen

      (center, g2) =
        case previousGap of
          Nothing ->
            randomR (loGap p, hiGap p) g1

          Just oldCenter ->
            nextGap p g1 oldCenter

      (phase, g3) = randomR (0, 2 * pi) g2
      gap = min (gapSize p) (stGap stage)

  in (mkPipe p x center kind gap phase, g3)

-- Sinh bay giua cac cot.
-- Khong sinh Fireball ngau nhien o man thuong.
-- Fireball cua boss van duoc GameLoop tao rieng.
spawnTrap :: Params -> Stage -> Int -> StdGen -> Pipe -> Pipe -> (Maybe Trap, StdGen)
spawnTrap p stage score gen previousPipe newPipe
  | null eligibleTrapWeights = (Nothing, gen)
  | otherwise =
      let (roll, g1) = randomR (0.0, 1.0 :: Double) gen
      in if roll >= max 0 (min 1 (stTrapChance stage))
           then (Nothing, g1)
           else
             let (kind, g2) =
                   pickWeighted eligibleTrapWeights g1

                 (sideRoll, g3) =
                   randomR (0, 1 :: Int) g2

                 (centerY, g4) =
                   randomR (loGap p, hiGap p) g3

                 x =
                   ( realToFrac (pipeX previousPipe)
                   + pipeWidthParam p
                   + realToFrac (pipeX newPipe)
                   ) / 2

                 y =
                   case kind of
                     CeilingSpikes ->
                       spikeHeight p / 2

                     FloorSpikes ->
                       screenH p - spikeHeight p / 2

                     StrongWind ->
                       screenH p / 2

                     Fireball ->
                       ( realToFrac (pipeGapTop previousPipe)
                       + realToFrac (pipeGapBottom previousPipe)
                       ) / 2

                     HunterBird ->
                       centerY

                 radius =
                   case kind of
                     Fireball ->
                       fireballRadius p

                     HunterBird ->
                       hunterRadius p

                     _ ->
                       max (spikeWidth p / 2) (windWidth p / 2)

                 _side = sideRoll

                 trap = Trap
                   { trapX = realToFrac x
                   , trapY = realToFrac y
                   , trapRadius = realToFrac radius
                   , trapKind = kind
                   , trapActive = True
                   }

             in (Just trap, g4)
  where
    -- Chi cho phep cac bay man thuong hop le.
    -- Loai Fireball va StrongWind khoi pool ngau nhien.
    eligibleTrapWeights =
      filter allowedTrap (stTrapWeights stage)

    allowedTrap (kind, weight) =
      kind /= StrongWind
        && kind /= Fireball
        && weight > 0

-- ============================================================
-- Trang thai cot ban dau
-- ============================================================

-- Ba cot dau tien, cach nhau 300 px.
initialPipes :: [Pipe]
initialPipes =
  [ Pipe 450 170 330 70 False NormalPipe 0 0 False
  , Pipe 750 210 370 70 False NormalPipe 0 0 False
  , Pipe 1050 150 310 70 False NormalPipe 0 0 False
  ]

-- Sinh bay giua cac cot dau tien.
initialTraps :: [Pipe] -> [Trap]
initialTraps pipes =
  fst (go pipes (mkStdGen 42))
  where
    stage = stageForScore 0

    go (previous:newPipe:rest) gen =
      let (maybeTrap, gen') =
            spawnTrap defaultParams stage 0 gen previous newPipe

          (remaining, finalGen) =
            go (newPipe:rest) gen'

      in (maybeToList maybeTrap ++ remaining, finalGen)

    go _ gen = ([], gen)

-- ============================================================
-- Cap nhat cot moi frame
-- ============================================================

pipeSpacingF :: Params -> Float
pipeSpacingF =
  realToFrac . pipeSpacing

scrollSpeed :: Stage -> Modifiers -> Float
scrollSpeed stage modifiers =
  realToFrac (stSpeed stage)
    * realToFrac (speedMul modifiers)

-- Di chuyen cot va tai su dung cot da ra khoi man hinh.
updatePipes
  :: Float
  -> Params
  -> Modifiers
  -> Stage
  -> Int
  -> [Pipe]
  -> ([Pipe], [Trap])

updatePipes dt params modifiers stage score pipes =
  let moved = map movePipe pipes

      recycledIndices =
        [ index
        | (index, pipe) <- zip [0 :: Int ..] moved
        , pipeX pipe + pipeWidth pipe < 0
        ]

  in foldl recycleOne (moved, []) recycledIndices
  where
    movePipe pipe =
      pipe
        { pipeX =
            pipeX pipe - scrollSpeed stage modifiers * dt

        , pipeAge =
            pipeAge pipe + dt
        }

    recycleOne (currentPipes, spawnedTraps) index =
      let oldPipe = currentPipes !! index

          others =
            [ pipe
            | (otherIndex, pipe) <-
                zip [0 :: Int ..] currentPipes
            , otherIndex /= index
            , pipeX pipe + pipeWidth pipe > 0
            ]

          previousPipe =
            case others of
              [] -> oldPipe
              _  -> maximumBy (comparing pipeX) others

          newX =
            pipeX previousPipe + pipeSpacingF params

          previousCenter =
            (pipeGapTop previousPipe + pipeGapBottom previousPipe) / 2

          seed =
            score * 7919
              + round (pipeX oldPipe * 100)
              + round (pipeAge oldPipe * 1000)
              + index * 104729

          gen0 = mkStdGen seed

          (newPipe, gen1) =
            spawnPipe
              params
              stage
              gen0
              (realToFrac newX)
              (Just (realToFrac previousCenter))

          (maybeTrap, _gen2) =
            spawnTrap
              params
              stage
              score
              gen1
              previousPipe
              newPipe

          updatedPipes =
            replaceAt index newPipe currentPipes

      in (updatedPipes, spawnedTraps ++ maybeToList maybeTrap)

    replaceAt index value values =
      take index values
        ++ [value]
        ++ drop (index + 1) values

-- ============================================================
-- Cap nhat bay
-- ============================================================

-- Fireball van duoc xu ly de phuc vu man boss.
updateTraps :: Float -> Params -> Modifiers -> Stage -> [Trap] -> [Trap]
updateTraps dt params modifiers stage =
  filter alive . map move
  where
    scroll = scrollSpeed stage modifiers

    move trap =
      let extraSpeed =
            case trapKind trap of
              Fireball ->
                negate (realToFrac (fireballSpeed params))

              HunterBird ->
                negate (realToFrac (hunterSpeed params))

              _ ->
                0

      in trap
           { trapX =
               trapX trap - (scroll - extraSpeed) * dt
           }

    alive trap =
      trapActive trap
        && trapX trap + trapRadius trap > 0

-- ============================================================
-- Tao lai cot sau man boss
-- ============================================================

respawnPipes :: Params -> Stage -> Int -> [Pipe]
respawnPipes params stage score =
  take 3 (build (0 :: Int) Nothing (mkStdGen (score * 7919 + 13)))
  where
    build :: Int -> Maybe Float -> StdGen -> [Pipe]

    build i _ _
      | i >= 3 = []

    build i prevCenter gen =
      let x =
            500 + fromIntegral i * pipeSpacingF params

          (pipe, gen') =
            spawnPipe
              params
              stage
              gen
              (realToFrac x)
              (fmap realToFrac prevCenter)

          center =
            (pipeGapTop pipe + pipeGapBottom pipe) / 2

      in pipe : build (i + 1) (Just center) gen'

-- ============================================================
-- Tinh diem khi vuot cot
-- ============================================================

scorePipes :: Bird -> [Pipe] -> Int
scorePipes bird =
  length . filter (passed bird)

markScored :: Bird -> [Pipe] -> [Pipe]
markScored bird =
  map mark
  where
    mark pipe
      | passed bird pipe =
          pipe { pipeScored = True }

      | otherwise =
          pipe

passed :: Bird -> Pipe -> Bool
passed bird pipe =
  not (pipeScored pipe)
    && pipeX pipe + pipeWidth pipe < birdX bird

-- ============================================================
-- Pha va don cot
-- ============================================================

destroyNearestPipe :: Float -> [Pipe] -> [Pipe]
destroyNearestPipe _ [] = []

destroyNearestPipe x pipes =
  let (_, nearestIndex) =
        foldl1 nearer
          (zip
            (map (abs . subtract x . pipeX) pipes)
            [0 :: Int ..])

  in take nearestIndex pipes
      ++ drop (nearestIndex + 1) pipes
  where
    nearer a b =
      if fst a <= fst b then a else b

breakPipeAhead :: Params -> [Pipe] -> [Pipe]
breakPipeAhead p pipes =
  case break isAhead pipes of
    (before, pipe:after) ->
      before ++ pipe { pipeBroken = True } : after

    (_, []) ->
      pipes
  where
    isAhead pipe =
      not (pipeBroken pipe)
        && realToFrac (pipeX pipe)
          + realToFrac (pipeWidth pipe)
          > birdFixedX p

clearTraps :: Params -> [Trap] -> [Trap]
clearTraps p =
  filter
    (\trap ->
      realToFrac (trapX trap)
        - realToFrac (trapExtent p)
        >= screenW p)
