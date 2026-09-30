{-# OPTIONS --safe #-}

module Shizuku.Manager.PermissionRequest where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Nat using (Nat)

record Request : Set where
  constructor request
  field
    uid          : Nat
    pid          : Nat
    request-code : Nat
    application-present : Bool

data UserChoice : Set where
  allow-persistent : UserChoice
  deny-one-time    : UserChoice

record Result : Set where
  constructor result
  field
    allowed  : Bool
    one-time : Bool

choice-result : UserChoice → Result
choice-result allow-persistent = result true false
choice-result deny-one-time = result false true

data Gate : Set where
  wait-for-binder : Gate
  invalid-request : Gate
  adb-limited     : Gate
  show-confirmation : Gate

decide :
  Bool → Bool → Request → Gate
decide binder-arrived can-grant-runtime request with binder-arrived
... | false = wait-for-binder
... | true with Request.application-present request
...   | false = invalid-request
...   | true with can-grant-runtime
...     | false = adb-limited
...     | true = show-confirmation

wait-timeout-seconds : Nat
wait-timeout-seconds = 5
