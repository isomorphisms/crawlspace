{-# OPTIONS --safe #-}

module Shizuku.Port.ShizukuProvider where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String; primStringEquality)

BinderHandle : Set
BinderHandle = Nat

method-send-binder : String
method-send-binder = "sendBinder"

method-get-binder : String
method-get-binder = "getBinder"

action-binder-received : String
action-binder-received = "moe.shizuku.api.action.BINDER_RECEIVED"

permission : String
permission = "moe.shizuku.manager.permission.API_V23"

manager-application-id : String
manager-application-id = "moe.shizuku.privileged.api"

record ProviderState : Set where
  constructor provider-state
  field
    binder                    : Maybe BinderHandle
    binder-alive              : Bool
    enable-multi-process      : Bool
    is-provider-process       : Bool
    automatic-sui-init        : Bool
    sui-active                : Bool

initial : ProviderState
initial =
  provider-state nothing false false false true false

data Effect : Set where
  shizuku-binder-received : BinderHandle → Effect
  broadcast-binder        : BinderHandle → Effect
  initialize-sui          : Effect

record Transition : Set where
  constructor transition
  field
    state   : ProviderState
    effects : List Effect

set-provider-process : Bool → ProviderState → ProviderState
set-provider-process provider state =
  provider-state
    (ProviderState.binder state)
    (ProviderState.binder-alive state)
    (ProviderState.enable-multi-process state)
    provider
    (ProviderState.automatic-sui-init state)
    (ProviderState.sui-active state)

enable-multiprocess : Bool → ProviderState → ProviderState
enable-multiprocess provider state =
  provider-state
    (ProviderState.binder state)
    (ProviderState.binder-alive state)
    true
    provider
    (ProviderState.automatic-sui-init state)
    (ProviderState.sui-active state)

disable-automatic-sui : ProviderState → ProviderState
disable-automatic-sui state =
  provider-state
    (ProviderState.binder state)
    (ProviderState.binder-alive state)
    (ProviderState.enable-multi-process state)
    (ProviderState.is-provider-process state)
    false
    (ProviderState.sui-active state)

receive-binder : BinderHandle → ProviderState → Transition
receive-binder binder state with ProviderState.binder-alive state
... | true = transition state []
... | false =
  transition
    (provider-state
      (just binder)
      true
      (ProviderState.enable-multi-process state)
      (ProviderState.is-provider-process state)
      (ProviderState.automatic-sui-init state)
      (ProviderState.sui-active state))
    effects
  where
  effects : List Effect
  effects with ProviderState.enable-multi-process state
  ... | true =
      shizuku-binder-received binder ∷
      broadcast-binder binder ∷ []
  ... | false = shizuku-binder-received binder ∷ []

get-binder : ProviderState → Maybe BinderHandle
get-binder state with ProviderState.binder-alive state
... | false = nothing
... | true = ProviderState.binder state

data CallResult : Set where
  null-reply  : CallResult
  empty-reply : CallResult
  binder-reply : BinderHandle → CallResult
  ok-reply    : CallResult

call : String → Maybe BinderHandle → ProviderState → CallResult
call method incoming state with ProviderState.sui-active state
... | true = empty-reply
... | false with primStringEquality method method-get-binder
...   | true with get-binder state
...     | nothing = null-reply
...     | just binder = binder-reply binder
...   | false with primStringEquality method method-send-binder
...     | true with incoming
...       | nothing = ok-reply
...       | just binder = ok-reply
...     | false = ok-reply
