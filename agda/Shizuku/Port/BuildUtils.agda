{-# OPTIONS --safe #-}

module Shizuku.Port.BuildUtils where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.Nat using (Nat)

open import Shizuku.Port.Prelude

record BuildVersion : Set where
  constructor build-version
  field
    sdk : Nat
    preview-sdk : Nat

at-least : Nat → BuildVersion → Bool
at-least wanted build = wanted ≤ᵇ BuildVersion.sdk build

at-least31 : BuildVersion → Bool
at-least31 build with 31 ≤ᵇ BuildVersion.sdk build
... | true = true
... | false with nat-eq (BuildVersion.sdk build) 30
...   | false = false
...   | true = 0 <ᵇ BuildVersion.preview-sdk build

at-least30 : BuildVersion → Bool
at-least30 = at-least 30

at-least29 : BuildVersion → Bool
at-least29 = at-least 29

at-least28 : BuildVersion → Bool
at-least28 = at-least 28

at-least26 : BuildVersion → Bool
at-least26 = at-least 26

at-least24 : BuildVersion → Bool
at-least24 = at-least 24

at-least23 : BuildVersion → Bool
at-least23 = at-least 23
