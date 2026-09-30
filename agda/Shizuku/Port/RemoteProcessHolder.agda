{-# OPTIONS --safe #-}

module Shizuku.Port.RemoteProcessHolder where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

BinderHandle : Set
BinderHandle = Nat

DescriptorHandle : Set
DescriptorHandle = Nat

data ProcessLife : Set where
  process-alive : ProcessLife
  process-exited : Nat → ProcessLife
  process-destroyed : ProcessLife

record Holder : Set where
  constructor holder
  field
    process-life : ProcessLife
    owner-token  : Maybe BinderHandle
    input-pipe   : Maybe DescriptorHandle
    output-pipe  : Maybe DescriptorHandle

data HolderEffect : Set where
  link-owner-death : BinderHandle → HolderEffect
  create-input-pipe : HolderEffect
  create-output-pipe : HolderEffect
  create-error-pipe : HolderEffect
  destroy-process : HolderEffect
  wait-process : HolderEffect

new-holder : Maybe BinderHandle → Holder
new-holder token = holder process-alive token nothing nothing

constructor-effects : Holder → Maybe HolderEffect
constructor-effects h with Holder.owner-token h
... | nothing = nothing
... | just token = just (link-owner-death token)

alive : Holder → Bool
alive h with Holder.process-life h
... | process-alive = true
... | process-exited _ = false
... | process-destroyed = false

owner-died : Holder → Maybe HolderEffect
owner-died h with alive h
... | true = just destroy-process
... | false = nothing

cache-output-pipe : DescriptorHandle → Holder → Holder
cache-output-pipe fd h =
  holder
    (Holder.process-life h)
    (Holder.owner-token h)
    (Holder.input-pipe h)
    (just fd)

cache-input-pipe : DescriptorHandle → Holder → Holder
cache-input-pipe fd h =
  holder
    (Holder.process-life h)
    (Holder.owner-token h)
    (just fd)
    (Holder.output-pipe h)

data TimeUnit : Set where
  nanoseconds : TimeUnit
  microseconds : TimeUnit
  milliseconds : TimeUnit
  seconds : TimeUnit
  minutes : TimeUnit
  hours : TimeUnit
  days : TimeUnit

record TimeoutRequest : Set where
  constructor timeout-request
  field
    timeout : Nat
    unit    : TimeUnit
