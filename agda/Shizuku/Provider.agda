{-# OPTIONS --safe #-}

module Shizuku.Provider where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat)

BinderHandle : Set
BinderHandle = Nat

data BinderState : Set where
  no-binder   : BinderState
  dead-binder : BinderState
  live-binder : BinderHandle → BinderState

record ProviderState : Set where
  constructor provider-state
  field
    binder        : BinderState
    multi-process : Bool

initial-provider : ProviderState
initial-provider = provider-state no-binder false

receive-binder : BinderHandle → ProviderState → ProviderState
receive-binder binder (provider-state (live-binder old) multi-process) =
  provider-state (live-binder old) multi-process
receive-binder binder (provider-state no-binder multi-process) =
  provider-state (live-binder binder) multi-process
receive-binder binder (provider-state dead-binder multi-process) =
  provider-state (live-binder binder) multi-process

binder-died : ProviderState → ProviderState
binder-died (provider-state no-binder multi-process) =
  provider-state no-binder multi-process
binder-died (provider-state dead-binder multi-process) =
  provider-state dead-binder multi-process
binder-died (provider-state (live-binder _) multi-process) =
  provider-state dead-binder multi-process

get-binder : ProviderState → Maybe BinderHandle
get-binder (provider-state (live-binder binder) _) = just binder
get-binder (provider-state no-binder _)            = nothing
get-binder (provider-state dead-binder _)          = nothing

enable-multi-process : ProviderState → ProviderState
enable-multi-process (provider-state binder _) =
  provider-state binder true

should-broadcast : ProviderState → Bool
should-broadcast (provider-state _ multi-process) = multi-process
