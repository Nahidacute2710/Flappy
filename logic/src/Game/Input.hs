module Input
    ( Key(..)
    , PointerEvent(..)
    , mapKeyInput
    , mapPointerInput
    ) where

import GameState (GameStatus(..), Input(..))

-- Frontend events are converted to these simple values before calling stepGame.
data Key
    = SpaceKey
    | ArrowUpKey
    | EnterKey
    | RestartKey
    | NumberKey Int
    | OtherKey
    deriving (Show, Eq)

data PointerEvent = MouseClick | OtherPointerEvent
    deriving (Show, Eq)

-- Click, Space, and ArrowUp share the same Flap action.
-- Number keys request a skill slot; currently slot 1 is the initial convention.
mapKeyInput :: GameStatus -> Key -> Input
mapKeyInput status key = case key of
    SpaceKey   -> flapOrStart status
    ArrowUpKey -> flapOrStart status
    EnterKey   -> if status == Ready then Start else NoInput
    RestartKey -> if status == GameOver then Restart else NoInput
    NumberKey n | status == Playing && n >= 1 && n <= 9 -> UseSkill n
    _ -> NoInput

mapPointerInput :: GameStatus -> PointerEvent -> Input
mapPointerInput status event = case event of
    MouseClick -> flapOrStart status
    OtherPointerEvent -> NoInput

flapOrStart :: GameStatus -> Input
flapOrStart Ready = Flap
flapOrStart Playing = Flap
flapOrStart GameOver = NoInput