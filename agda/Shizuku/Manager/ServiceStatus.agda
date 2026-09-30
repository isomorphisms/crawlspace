{-# OPTIONS --safe #-}

module Shizuku.Manager.ServiceStatus where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.Maybe using (Maybe)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

data KnownNat : Set where
  unknown : KnownNat
  known   : Nat → KnownNat

record ServiceStatus : Set where
  constructor service-status
  field
    uid          : KnownNat
    api-version  : KnownNat
    patch-version : KnownNat
    se-context   : Maybe String
    permission   : Bool
    binder-alive : Bool

is-running : ServiceStatus → Bool
is-running status with ServiceStatus.uid status
... | unknown = false
... | known _ = ServiceStatus.binder-alive status
