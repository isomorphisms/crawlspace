{-# OPTIONS --safe #-}

module Shizuku.Port.UserHandleCompat where

open import Agda.Builtin.Nat using (Nat; zero; suc)

per-user-range : Nat
per-user-range = 100000

record UidParts : Set where
  constructor uid-parts
  field
    user-id : Nat
    app-id  : Nat

recompose : UidParts → Nat
recompose parts =
  (UidParts.user-id parts * per-user-range) + UidParts.app-id parts
  where
  _+_ : Nat → Nat → Nat
  zero + b = b
  suc a + b = suc (a + b)

  _*_ : Nat → Nat → Nat
  zero * b = zero
  suc a * b = b + (a * b)
