{-# OPTIONS --safe #-}

module Shizuku.Manager.SystemApis where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

record UserInfo : Set where
  constructor user-info
  field
    id   : Nat
    name : String

fallback-user : Nat → UserInfo
fallback-user my-user = user-info my-user "Owner"

data Call : Set where
  get-users                : Bool → Call
  get-installed-packages   : Nat → Nat → Call
  check-permission         : String → String → Nat → Call
  grant-runtime-permission : String → String → Nat → Call
  revoke-runtime-permission : String → String → Nat → Call

data Availability : Set where
  binder-missing : Availability
  binder-ready   : Availability

may-call : Availability → Call → Bool
may-call binder-missing _ = false
may-call binder-ready _ = true

record UserCache : Set where
  constructor user-cache
  field
    users : List UserInfo

should-refresh-users : Bool → UserCache → Bool
should-refresh-users use-cache cache with use-cache
... | false = true
... | true with UserCache.users cache
...   | [] = true
...   | _ ∷ _ = false
