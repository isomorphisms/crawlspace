{-# OPTIONS --safe #-}

module Shizuku.Port.ShellLoader where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String; primStringEquality)

open import Shizuku.Port.Prelude

BinderHandle : Set
BinderHandle = Nat

data PackageResolution : Set where
  package-ok    : String → PackageResolution
  package-error : PackageResolution

resolve-package :
  List String → Maybe String → PackageResolution
resolve-package (only ∷ []) environment = package-ok only
resolve-package packages nothing = package-error
resolve-package packages (just environment) with primStringEquality environment ""
... | true = package-error
... | false with primStringEquality environment "PKG"
...   | true = package-error
...   | false = package-ok environment

data RequestMethod : Set where
  broadcast-request : RequestMethod
  chooser-activity-request : RequestMethod

record BroadcastFailure : Set where
  constructor broadcast-failure
  field
    sdk                 : Nat
    package-name-error  : Bool

fallback-method : BroadcastFailure → Maybe RequestMethod
fallback-method failure with nat-eq (BroadcastFailure.sdk failure) 26
... | true with BroadcastFailure.package-name-error failure
...   | true = just chooser-activity-request
...   | false = nothing
... | false with nat-eq (BroadcastFailure.sdk failure) 27
...   | true with BroadcastFailure.package-name-error failure
...     | true = just chooser-activity-request
...     | false = nothing
...   | false = nothing

record ShellLoadPlan : Set where
  constructor shell-load-plan
  field
    source-dir          : String
    instruction-set     : String
    system-library-path : Maybe String
    class-name          : String
    method-name         : String

make-shell-load-plan :
  String → String → Maybe String → ShellLoadPlan
make-shell-load-plan source instruction-set library-path =
  shell-load-plan
    source
    instruction-set
    library-path
    "moe.shizuku.manager.shell.Shell"
    "main"

data BinderReceive : Set where
  server-not-running : BinderReceive
  load-shell : BinderHandle → ShellLoadPlan → BinderReceive

request-timeout-millis : Nat
request-timeout-millis = 5000
