module Config
  ( Params(..)
  , Modifiers(..)
  , defaultParams
  , defaultModifiers
  ) where

-- GameState is the single source of truth for these shared definitions.
-- This module remains as a compatibility re-export for modules that import Config.
import GameState (Params(..), Modifiers(..), defaultParams, defaultModifiers)
