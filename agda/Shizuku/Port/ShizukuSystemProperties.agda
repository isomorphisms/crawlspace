{-# OPTIONS --safe #-}

module Shizuku.Port.ShizukuSystemProperties where

open import Agda.Builtin.Bool using (Bool)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

data PropertyCall : Set where
  get-string : String → String → PropertyCall
  get-int    : String → Nat → PropertyCall
  get-long   : String → Nat → PropertyCall
  get-bool   : String → Bool → PropertyCall
  set        : String → String → PropertyCall

remote-get : String → String → PropertyCall
remote-get key default = get-string key default
