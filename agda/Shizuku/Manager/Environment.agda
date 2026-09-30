{-# OPTIONS --safe #-}

module Shizuku.Manager.Environment where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

record PathEntry : Set where
  constructor path-entry
  field
    path   : String
    has-su : Bool

is-rooted : List PathEntry → Bool
is-rooted [] = false
is-rooted (entry ∷ rest) with PathEntry.has-su entry
... | true = true
... | false = is-rooted rest

data PropertyInt : Set where
  missing : PropertyInt
  value   : Nat → PropertyInt

adb-tcp-port : PropertyInt → PropertyInt → PropertyInt
adb-tcp-port (value port) persistent = value port
adb-tcp-port missing persistent = persistent
