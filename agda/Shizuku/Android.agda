{-# OPTIONS --safe #-}

module Shizuku.Android where

open import Agda.Builtin.Bool using (Bool)
open import Agda.Builtin.List using (List)
open import Agda.Builtin.String using (String)

open import Shizuku.Types
import Shizuku.Protocol

record AndroidOps : Set₁ where
  field
    Action      : Set
    Binder      : Set
    Process     : Set

    calling-uid : Uid
    calling-pid : Pid

    packages-for-uid : Uid → List PackageName
    package-owned-by : Uid → PackageName → Set

    binder-alive : Binder → Bool

    check-runtime-permission :
      PermissionName → Pid → Uid → Bool

    wait-system-service : String → Action
    spawn               : Shizuku.Protocol.ProcessSpec → Process

    deliver-binder :
      PackageName → Binder → Action

    force-stop-package :
      PackageName → UserId → Action

    grant-runtime-permission :
      PackageName → PermissionName → UserId → Action

    revoke-runtime-permission :
      PackageName → PermissionName → UserId → Action

    get-selinux-context : SELinuxContext
    get-system-property : String → String → String
    set-system-property : String → String → Action
