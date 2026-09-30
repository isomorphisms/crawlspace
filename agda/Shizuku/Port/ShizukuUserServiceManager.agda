{-# OPTIONS --safe #-}

module Shizuku.Port.ShizukuUserServiceManager where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

open import Shizuku.Port.Prelude
open import Shizuku.Port.ServiceStarter
open import Shizuku.Port.UserServiceRecord

record PackageLocation : Set where
  constructor package-location
  field
    package-name : String
    source-dir   : String

find-package-location :
  String → List PackageLocation → Maybe String
find-package-location package-name [] = nothing
find-package-location package-name (location ∷ rest)
  with string-eq package-name (PackageLocation.package-name location)
... | true = just (PackageLocation.source-dir location)
... | false = find-package-location package-name rest

data ApkEffect : Set where
  start-apk-observer : String → String → ApkEffect
  stop-apk-observer  : String → ApkEffect
  remove-service-record : String → ApkEffect

record ApkWatch : Set where
  constructor apk-watch
  field
    token        : String
    package-name : String
    source-dir   : String

record ApkTransition : Set where
  constructor apk-transition
  field
    watch   : Maybe ApkWatch
    effects : List ApkEffect

record-created :
  String → String → String → ApkTransition
record-created token package-name source-dir =
  apk-transition
    (just (apk-watch token package-name source-dir))
    (start-apk-observer token source-dir ∷ [])

apk-changed :
  ApkWatch → List PackageLocation → ApkTransition
apk-changed watch locations
  with find-package-location (ApkWatch.package-name watch) locations
... | nothing =
  apk-transition
    nothing
    (stop-apk-observer (ApkWatch.token watch) ∷
     remove-service-record (ApkWatch.token watch) ∷ [])
... | just new-source =
  apk-transition
    (just
      (apk-watch
        (ApkWatch.token watch)
        (ApkWatch.package-name watch)
        new-source))
    (stop-apk-observer (ApkWatch.token watch) ∷
     start-apk-observer (ApkWatch.token watch) new-source ∷ [])

record-removed : ApkWatch → ApkTransition
record-removed watch =
  apk-transition
    nothing
    (stop-apk-observer (ApkWatch.token watch) ∷ [])
