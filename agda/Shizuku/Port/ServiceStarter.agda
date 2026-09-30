{-# OPTIONS --safe #-}

module Shizuku.Port.ServiceStarter where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

open import Shizuku.Port.Prelude
open import Shizuku.Port.BuildUtils

data DebugMode : Set where
  adbconnection-jdwp : DebugMode
  internal-jdwp      : DebugMode
  legacy-jdwp        : DebugMode

debug-mode : BuildVersion → DebugMode
debug-mode build with 30 ≤ᵇ BuildVersion.sdk build
... | true = adbconnection-jdwp
... | false with 28 ≤ᵇ BuildVersion.sdk build
...   | true = internal-jdwp
...   | false = legacy-jdwp

data AppProcess : Set where
  app-process   : AppProcess
  app-process32 : AppProcess

choose-app-process : Bool → Bool → AppProcess
choose-app-process use32 app-process32-exists with use32 && app-process32-exists
... | true = app-process32
... | false = app-process

record UserServiceCommand : Set where
  constructor user-service-command
  field
    app-process         : AppProcess
    manager-apk-path    : String
    token               : String
    package-name        : String
    class-name          : String
    process-name-suffix : String
    calling-uid         : Nat
    debug               : Bool
    debug-mode          : DebugMode

make-user-service-command :
  BuildVersion →
  Bool →
  Bool →
  String →
  String →
  String →
  String →
  String →
  Nat →
  Bool →
  UserServiceCommand
make-user-service-command
  build use32 app-process32-exists manager-apk token package-name
  class-name suffix uid debug =
  user-service-command
    (choose-app-process use32 app-process32-exists)
    manager-apk
    token
    package-name
    class-name
    suffix
    uid
    debug
    (debug-mode build)

data SendStage : Set where
  first-attempt : SendStage
  retry-after-force-stop : SendStage

data ProviderState : Set where
  provider-missing : ProviderState
  provider-dead    : ProviderState
  provider-alive   : ProviderState

data SendDecision : Set where
  fail-send       : SendDecision
  force-stop-retry : SendDecision
  call-provider   : SendDecision

send-decision : SendStage → ProviderState → SendDecision
send-decision _ provider-missing = fail-send
send-decision first-attempt provider-dead = force-stop-retry
send-decision retry-after-force-stop provider-dead = fail-send
send-decision _ provider-alive = call-provider

data BinderReply : Set where
  no-reply          : BinderReply
  missing-server    : BinderReply
  dead-server       : BinderReply
  live-server       : BinderReply

send-succeeded : BinderReply → Bool
send-succeeded live-server = true
send-succeeded _ = false
