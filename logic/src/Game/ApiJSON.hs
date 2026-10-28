{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE UndecidableInstances #-}
module ApiJSON () where

import Data.Aeson (FromJSON(..), ToJSON(..), Value(..), object, withObject, (.:), (.=))
import GameState

-- Generic JSON instances keep the complete GameState round-trippable.
-- Nullary constructors such as GameStatus and Background use JSON strings.
-- Record field names stay identical to the Haskell selectors.
instance ToJSON Rarity
instance FromJSON Rarity
instance ToJSON BirdKind
instance FromJSON BirdKind
instance ToJSON SkillType
instance FromJSON SkillType
instance ToJSON Bird
instance FromJSON Bird
instance ToJSON PipeKind
instance FromJSON PipeKind
instance ToJSON Pipe
instance FromJSON Pipe
instance ToJSON TrapKind
instance FromJSON TrapKind
instance ToJSON Trap
instance FromJSON Trap
instance ToJSON CurrencyKind
instance FromJSON CurrencyKind
instance ToJSON Coin
instance FromJSON Coin
instance ToJSON ItemKind
instance FromJSON ItemKind
instance ToJSON ItemPickup
instance FromJSON ItemPickup
instance ToJSON ActiveEffect
instance FromJSON ActiveEffect
instance ToJSON Background
instance FromJSON Background
instance ToJSON Boss
instance FromJSON Boss
instance ToJSON DangerLevel
instance FromJSON DangerLevel
instance ToJSON Decision
instance FromJSON Decision
instance ToJSON GameStatus
instance FromJSON GameStatus
-- Input is deliberately friendly to the browser API: simple actions are strings;
-- skill activation is an object such as {"UseSkill":1}.
instance ToJSON Input where
  toJSON NoInput = String "NoInput"
  toJSON Flap = String "Flap"
  toJSON Start = String "Start"
  toJSON Restart = String "Restart"
  toJSON (UseSkill n) = object ["UseSkill" .= n]

instance FromJSON Input where
  parseJSON (String name) = case name of
    "NoInput" -> pure NoInput
    "Flap" -> pure Flap
    "Start" -> pure Start
    "Restart" -> pure Restart
    _ -> fail "input must be NoInput, Flap, Start, Restart, or {\"UseSkill\":slot}"
  parseJSON value = withObject "Input" (\o -> UseSkill <$> o .: "UseSkill") value
instance ToJSON Params
instance FromJSON Params
instance ToJSON Modifiers
instance FromJSON Modifiers
instance ToJSON GameState
instance FromJSON GameState