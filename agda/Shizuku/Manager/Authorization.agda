{-# OPTIONS --safe #-}

module Shizuku.Manager.Authorization where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

open import Shizuku.Port.Prelude

data Backend : Set where
  pre-v11 : Backend
  v11-patch : Nat → Backend
  modern : Backend

use-server-application-list : Backend → Bool
use-server-application-list pre-v11 = false
use-server-application-list (v11-patch patch) = 3 ≤ᵇ patch
use-server-application-list modern = true

data PermissionAction : Set where
  legacy-check : String → Nat → PermissionAction
  server-get-flags : Nat → PermissionAction
  legacy-grant : String → Nat → PermissionAction
  server-grant : Nat → PermissionAction
  legacy-revoke : String → Nat → PermissionAction
  server-revoke : Nat → PermissionAction

granted-plan : Backend → String → Nat → Nat → PermissionAction
granted-plan pre-v11 package-name uid user-id =
  legacy-check package-name user-id
granted-plan (v11-patch _) package-name uid user-id =
  server-get-flags uid
granted-plan modern package-name uid user-id =
  server-get-flags uid

grant-plan : Backend → String → Nat → Nat → PermissionAction
grant-plan pre-v11 package-name uid user-id =
  legacy-grant package-name user-id
grant-plan (v11-patch _) package-name uid user-id =
  server-grant uid
grant-plan modern package-name uid user-id =
  server-grant uid

revoke-plan : Backend → String → Nat → Nat → PermissionAction
revoke-plan pre-v11 package-name uid user-id =
  legacy-revoke package-name user-id
revoke-plan (v11-patch _) package-name uid user-id =
  server-revoke uid
revoke-plan modern package-name uid user-id =
  server-revoke uid

flag-allowed : Nat
flag-allowed = 2

flag-denied : Nat
flag-denied = 4

mask-permission : Nat
mask-permission = 6
