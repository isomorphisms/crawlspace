{-# OPTIONS --safe #-}

module Shizuku.Manager.Settings where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.String using (String; primStringEquality)

data LaunchMethod : Set where
  unknown : LaunchMethod
  root    : LaunchMethod
  adb     : LaunchMethod

data NightMode : Set where
  follow-system : NightMode
  night-yes     : NightMode
  stored-mode   : String → NightMode

default-night-mode : Bool → NightMode
default-night-mode is-watch with is-watch
... | true = night-yes
... | false = follow-system

data LocaleChoice : Set where
  system-locale : LocaleChoice
  language-tag  : String → LocaleChoice

locale-choice : Maybe String → LocaleChoice
locale-choice nothing = system-locale
locale-choice (just tag) with primStringEquality tag ""
... | true = system-locale
... | false with primStringEquality tag "SYSTEM"
...   | true = system-locale
...   | false = language-tag tag

settings-name : String
settings-name = "settings"

night-mode-key : String
night-mode-key = "night_mode"

language-key : String
language-key = "language"

start-on-boot-key : String
start-on-boot-key = "start_on_boot"
