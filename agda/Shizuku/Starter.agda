{-# OPTIONS --safe #-}

module Shizuku.Starter where

open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.String using (String)

open import Shizuku.Types

data Bootstrap : Set where
  adb-start  : Bootstrap
  root-start : Bootstrap

data RequiredService : Set where
  package-service  : RequiredService
  activity-service : RequiredService
  user-service     : RequiredService
  app-ops-service  : RequiredService

required-services : List RequiredService
required-services =
  package-service ∷
  activity-service ∷
  user-service ∷
  app-ops-service ∷
  []

data StartStage : Set where
  wait-for-system-services : StartStage
  find-manager             : StartStage
  launch-server            : StartStage
  publish-binder           : StartStage
  serve-clients            : StartStage

startup-plan : List StartStage
startup-plan =
  wait-for-system-services ∷
  find-manager ∷
  launch-server ∷
  publish-binder ∷
  serve-clients ∷
  []

record StartContext : Set where
  constructor start-context
  field
    bootstrap       : Bootstrap
    identity        : ServerIdentity
    manager-package : PackageName
    server-main     : String
