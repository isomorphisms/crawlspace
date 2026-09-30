{-# OPTIONS --safe #-}

module Shizuku.Port.ShizukuRemoteProcess where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat)

RemoteHandle : Set
RemoteHandle = Nat

StreamHandle : Set
StreamHandle = Nat

record State : Set where
  constructor process-state
  field
    remote        : Maybe RemoteHandle
    output-stream : Maybe StreamHandle
    input-stream  : Maybe StreamHandle
    cached        : Bool

new : RemoteHandle → State
new remote = process-process-state (just remote) nothing nothing true

remote-died : State → State
remote-died old =
  process-process-state nothing
    (State.output-stream old)
    (State.input-stream old)
    false

cache-output-stream : StreamHandle → State → State
cache-output-stream stream old =
  process-process-state (State.remote old)
    (just stream)
    (State.input-stream old)
    (State.cached old)

cache-input-stream : StreamHandle → State → State
cache-input-stream stream old =
  process-process-state (State.remote old)
    (State.output-stream old)
    (just stream)
    (State.cached old)

data Call : Set where
  get-output-stream : Call
  get-input-stream  : Call
  get-error-stream  : Call
  wait-for          : Call
  exit-value        : Call
  destroy           : Call
  alive             : Call
  wait-for-timeout  : Nat → Call
  as-binder         : Call

data Availability : Set where
  remote-available : RemoteHandle → Availability
  remote-dead      : Availability

availability : State → Availability
availability state with State.remote state
... | nothing = remote-dead
... | just remote = remote-available remote
