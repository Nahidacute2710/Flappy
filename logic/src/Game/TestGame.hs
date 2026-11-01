
module Main (main) where

import qualified PipeSystem as PS
import GameLoop (initialGameState, stepGame, activateSkill)
import GameState

import Control.Monad (unless)
import System.Exit (exitFailure)

-- Kiem tra mot dieu kien va in ket qua.
check :: String -> Bool -> IO Bool
check name condition = do
  putStrLn $
    (if condition then "PASS: " else "FAIL: ") ++ name
  pure condition

main :: IO ()
main = do
  putStrLn "===== KIEM THU LOGIC GAME ====="

  let initial = initialGameState

  -- 1. Trang thai ban dau.
  t1 <- check "Trang thai ban dau la Ready"
    (gameStatus initial == Ready)

  t2 <- check "Diem ban dau bang 0"
    (gameScore initial == 0)

  t3 <- check "Tien ban dau bang 0"
    (gameGold initial == 0
      && gameDiamonds initial == 0
      && gameFeathers initial == 0)

  -- 2. Khong co input thi game chua bat dau.
  let readyAfterTick = stepGame NoInput initial

  t4 <- check "NoInput khong lam game bat dau"
    (readyAfterTick == initial)

  -- 3. Bat dau choi.
  let started = stepGame Start initial

  t5 <- check "Start chuyen sang Playing"
    (gameStatus started == Playing)

  t6 <- check "Start khong tu tang diem"
    (gameScore started == 0)

  -- 4. Flap khi Ready.
  let flapped = stepGame Flap initial

  t7 <- check "Flap tu Ready bat dau game"
    (gameStatus flapped == Playing)

  t8 <- check "Flap tao van toc bay len"
    (birdVelocity (gameBird flapped) < 0)

  -- 5. Trang thai GameOver.
  let dead = started
        { gameStatus = GameOver
        , gameScore = 15
        }

  t9 <- check "GameOver khong cap nhat khi NoInput"
    (stepGame NoInput dead == dead)

  t10 <- check "GameOver khong cho Flap tiep"
    (stepGame Flap dead == dead)

  -- 6. Restart.
  let restarted = stepGame Restart dead

  t11 <- check "Restart dua game ve Ready"
    (gameStatus restarted == Ready)

  t12 <- check "Restart dat diem ve 0"
    (gameScore restarted == 0)

  -- 7. Restart giu lai loai chim va skill.
  let specialBird = birdWithKind Owl
      specialState = dead { gameBird = specialBird }
      restartedSpecial = stepGame Restart specialState

  t13 <- check "Restart giu loai chim da chon"
    (birdKind (gameBird restartedSpecial) == Owl)

  t14 <- check "Restart giu skill cua chim"
    (birdSkill (gameBird restartedSpecial) == CoinMagnet)

  -- 8. Restart giu trang thai bat tu.
  let immortalState = dead { gameImmortal = True }
      restartedImmortal = stepGame Restart immortalState

  t15 <- check "Restart giu trang thai bat tu"
    (gameImmortal restartedImmortal)

  -- 9. UseSkill khi Ready.
  t16 <- check "UseSkill khi Ready khong lam bat dau game"
    (stepGame (UseSkill 1) initial == initial)

  -- 10. Chim cham dat.
  let fallingBird = (gameBird started)
        { birdY = screenHeight + 50
        }

      fallingState = started
        { gameBird = fallingBird
        , gamePipes = []
        , gameTraps = []
        , gameItems = []
        , gameCoins = []
        }

      afterCollision = stepGame NoInput fallingState

  t17 <- check "Chim cham dat thi GameOver"
    (gameStatus afterCollision == GameOver)

  -- 11. GameOver giu nguyen diem.
  let finishedState = dead { gameScore = 25 }

  t18 <- check "GameOver giu nguyen diem"
    (gameScore (stepGame NoInput finishedState) == 25)

  -- 12. Chua du no thi khong duoc kich hoat skill.
  let skillBird = birdWithKind Owl
      skillState = started
        { gameBird = skillBird
        , gameRage = 0
        }

  t19 <- check "Khong du no thi khong kich hoat skill"
    (activateSkill 1 skillState == skillState)

  -- 13. Cot da nam hoan toan sau chim duoc 1 diem.
  let testBird = gameBird initial

      passedPipe = Pipe 20 170 330 70 False NormalPipe 0 0 False

  t20 <- check "Vuot qua mot cot duoc 1 diem"
    (PS.scorePipes testBird [passedPipe] == 1)

  -- 14. Cot o phia truoc chua duoc tinh diem.
  let upcomingPipe = passedPipe
        { pipeX = 200
        }

  t21 <- check "Chua vuot cot thi khong cong diem"
    (PS.scorePipes testBird [upcomingPipe] == 0)

  -- 15. Cot da tinh diem khong duoc tinh lan hai.
  let markedPipes = PS.markScored testBird [passedPipe]

  t22 <- check "Khong cong diem hai lan cho cung mot cot"
    (PS.scorePipes testBird markedPipes == 0)

  -- 16. Dem dung so cot da vuot qua.
  let secondPipe = passedPipe
        { pipeX = 40
        }

  t23 <- check "Vuot qua hai cot duoc 2 diem"
    (PS.scorePipes testBird [passedPipe, secondPipe] == 2)

  -- Tong hop ket qua.
  let results =
        [ t1, t2, t3, t4
        , t5, t6, t7, t8
        , t9, t10, t11, t12
        , t13, t14, t15, t16
        , t17, t18, t19
        , t20, t21, t22, t23
        ]

      passed = length (filter id results)
      total = length results

  putStrLn ""
  putStrLn "===== TONG KET ====="
  putStrLn $
    "So test dung: " ++ show passed ++ "/" ++ show total

  unless (and results) exitFailure
