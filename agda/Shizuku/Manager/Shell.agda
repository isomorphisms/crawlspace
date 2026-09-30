{-# OPTIONS --safe #-}

module Shizuku.Manager.Shell where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.Nat using (Nat)

open import Shizuku.Port.Prelude

data PermissionState : Set where
  granted : PermissionState
  denied-with-rationale : PermissionState
  request-needed : PermissionState

data PermissionAction : Set where
  run-shell : PermissionAction
  exit-permission-denied : PermissionAction
  add-result-listener-and-request : Nat → PermissionAction

permission-plan : PermissionState → PermissionAction
permission-plan granted = run-shell
permission-plan denied-with-rationale = exit-permission-denied
permission-plan request-needed = add-result-listener-and-request 0

data VersionDecision : Set where
  version-ok : VersionDecision
  server-too-old : Nat → VersionDecision

check-server-version : Nat → VersionDecision
check-server-version version with 12 ≤ᵇ version
... | true = version-ok
... | false = server-too-old version
