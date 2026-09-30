{-# OPTIONS --safe #-}

module Shizuku.Manager.Boot where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Nat using (Nat)

open import Shizuku.Port.Prelude
open import Shizuku.Manager.Settings

data BootAction : Set where
  locked-boot-completed : BootAction
  boot-completed        : BootAction
  other-action          : BootAction

record Facts : Set where
  constructor facts
  field
    action                  : BootAction
    user-id                 : Nat
    binder-running          : Bool
    launch-method           : LaunchMethod
    sdk                     : Nat
    write-secure-settings   : Bool
    root-available          : Bool

data Effect : Set where
  no-start : Effect
  close-cached-root-shell : Effect
  run-root-command : Effect
  enable-adb-wifi : Effect
  enable-adb : Effect
  remove-adb-time-limit : Effect
  discover-adb-tls-port : Effect
  run-adb-command : Effect

eligible-plan : Facts → List Effect
eligible-plan f with nat-eq (Facts.user-id f) 0
... | false = no-start ∷ []
... | true with Facts.binder-running f
...   | true = no-start ∷ []
...   | false with Facts.launch-method f
...     | root with Facts.root-available f
...       | true = run-root-command ∷ []
...       | false = close-cached-root-shell ∷ []
...     | adb with 33 ≤ᵇ Facts.sdk f
...       | false = no-start ∷ []
...       | true with Facts.write-secure-settings f
...         | false = no-start ∷ []
...         | true =
            enable-adb-wifi ∷
            enable-adb ∷
            remove-adb-time-limit ∷
            discover-adb-tls-port ∷
            run-adb-command ∷ []
...     | unknown = no-start ∷ []

boot-plan : Facts → List Effect
boot-plan f with Facts.action f
... | other-action = no-start ∷ []
... | locked-boot-completed = eligible-plan f
... | boot-completed = eligible-plan f
