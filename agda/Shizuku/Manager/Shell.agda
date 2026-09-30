{-# OPTIONS --safe #-}

module Shizuku.Manager.Shell where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.Nat using (Nat)

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
check-server-version version with less-than-12 version
... | true = server-too-old version
... | false = version-ok
  where
  less-than-12 : Nat → Bool
  less-than-12 zero = true
  less-than-12 (Agda.Builtin.Nat.suc n) = go n
    where
    go : Nat → Bool
    go zero = true
    go (Agda.Builtin.Nat.suc zero) = true
    go (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc zero)) = true
    go (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc zero))) = true
    go (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc zero)))) = true
    go (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc zero))))) = true
    go (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc zero)))))) = true
    go (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc zero))))))) = true
    go (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc zero)))))))) = true
    go (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc zero))))))))) = true
    go (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc (Agda.Builtin.Nat.suc zero)))))))))) = true
    go _ = false
