{-# OPTIONS --safe #-}

module Shizuku.Port.BinderWrapper where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.Nat using (Nat)

open import Shizuku.Port.Prelude

BinderHandle : Set
BinderHandle = Nat

record ClientVersion : Set where
  constructor client-version
  field
    pre-v11        : Bool
    server-version : Nat

at-least13 : ClientVersion → Bool
at-least13 version =
  not (ClientVersion.pre-v11 version)
  &&
  (13 ≤ᵇ ClientVersion.server-version version)

record RemoteEnvelope : Set where
  constructor remote-envelope
  field
    original-binder : BinderHandle
    target-code     : Nat
    target-flags    : Nat
    include-flags   : Bool
    outer-flags     : Nat

wrap :
  ClientVersion → BinderHandle → Nat → Nat → RemoteEnvelope
wrap version binder code flags with at-least13 version
... | true =
  remote-envelope binder code flags true 0
... | false =
  remote-envelope binder code flags false flags
