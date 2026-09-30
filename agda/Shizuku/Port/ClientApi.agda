{-# OPTIONS --safe #-}

module Shizuku.Port.ClientApi where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

open import Shizuku.Port.Prelude

BinderHandle : Set
BinderHandle = Nat

data CachedNat : Set where
  unknown-nat : CachedNat
  known-nat   : Nat → CachedNat

record State : Set where
  constructor client-state
  field
    binder          : Maybe BinderHandle
    binder-ready    : Bool
    pre-v11         : Bool
    server-uid      : CachedNat
    server-version  : CachedNat
    server-context  : Maybe String
    permission-granted : Bool
    show-rationale     : Bool

initial : State
initial =
  client-client-state nothing false false unknown-nat unknown-nat nothing false false

data Effect : Set where
  link-death                 : BinderHandle → Effect
  unlink-old-death           : BinderHandle → Effect
  try-attach-v13             : BinderHandle → String → Effect
  try-attach-v11             : BinderHandle → String → Effect
  notify-binder-received     : Effect
  notify-binder-dead         : Effect
  notify-permission-result   : Nat → Bool → Effect

record Transition : Set where
  constructor transition
  field
    state   : State
    effects : List Effect

binder-lost : State → Transition
binder-lost old =
  transition
    (client-client-state nothing false (State.pre-v11 old)
      unknown-nat unknown-nat nothing false false)
    (notify-binder-dead ∷ [])

binder-received : BinderHandle → String → State → Transition
binder-received new-binder package-name old with State.binder old
... | nothing =
  transition
    (client-client-state (just new-binder) false (State.pre-v11 old)
      unknown-nat unknown-nat nothing
      (State.permission-granted old)
      (State.show-rationale old))
    (link-death new-binder ∷
     try-attach-v13 new-binder package-name ∷
     try-attach-v11 new-binder package-name ∷ [])
... | just old-binder =
  transition
    (client-client-state (just new-binder) false (State.pre-v11 old)
      unknown-nat unknown-nat nothing
      (State.permission-granted old)
      (State.show-rationale old))
    (unlink-old-death old-binder ∷
     link-death new-binder ∷
     try-attach-v13 new-binder package-name ∷
     try-attach-v11 new-binder package-name ∷ [])

attach-both-failed : State → Transition
attach-both-failed old =
  transition
    (client-state
      (State.binder old)
      true
      true
      (State.server-uid old)
      (State.server-version old)
      (State.server-context old)
      (State.permission-granted old)
      (State.show-rationale old))
    (notify-binder-received ∷ [])

record BindApplicationReply : Set where
  constructor bind-application-reply
  field
    server-uid     : Nat
    server-version : Nat
    server-context : String
    permission-granted : Bool
    show-rationale     : Bool

bind-application : BindApplicationReply → State → Transition
bind-application reply old =
  transition
    (client-state
      (State.binder old)
      true
      false
      (known-nat (BindApplicationReply.server-uid reply))
      (known-nat (BindApplicationReply.server-version reply))
      (just (BindApplicationReply.server-context reply))
      (BindApplicationReply.permission-granted reply)
      (BindApplicationReply.show-rationale reply))
    (notify-binder-received ∷ [])

permission-result : Nat → Bool → State → Transition
permission-result request-code allowed old =
  transition
    (client-state
      (State.binder old)
      (State.binder-ready old)
      (State.pre-v11 old)
      (State.server-uid old)
      (State.server-version old)
      (State.server-context old)
      allowed
      (State.show-rationale old))
    (notify-permission-result request-code allowed ∷ [])

data UserServiceUnbindMode : Set where
  remove-service : UserServiceUnbindMode
  detach-only    : UserServiceUnbindMode

record ServerCompatibility : Set where
  constructor server-compatibility
  field
    version : Nat
    patch   : Nat

server-supports-detach : ServerCompatibility → Bool
server-supports-detach compat with 14 ≤ᵇ ServerCompatibility.version compat
... | true = true
... | false with nat-eq (ServerCompatibility.version compat) 13
...   | false = false
...   | true = 4 ≤ᵇ ServerCompatibility.patch compat

data UnbindEffect : Set where
  call-remove-user-service : Bool → UnbindEffect
  clear-local-connections  : UnbindEffect
  remove-local-cache       : UnbindEffect

unbind-plan :
  UserServiceUnbindMode → ServerCompatibility → List UnbindEffect
unbind-plan remove-service compat =
  call-remove-user-service true ∷ []
unbind-plan detach-only compat with server-supports-detach compat
... | true =
  call-remove-user-service false ∷
  clear-local-connections ∷
  remove-local-cache ∷ []
... | false =
  clear-local-connections ∷
  remove-local-cache ∷ []

data PeekCompatibility : Set where
  pre13 : PeekCompatibility
  v13plus : PeekCompatibility

normalize-peek-running : PeekCompatibility → Bool → Nat
normalize-peek-running v13plus server-says-running = 0
normalize-peek-running pre13 true = 0
normalize-peek-running pre13 false = 1
