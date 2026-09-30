{-# OPTIONS --safe #-}

module Shizuku.Port.ServiceConnection where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

open import Shizuku.Port.Prelude

BinderHandle : Set
BinderHandle = Nat

ConnectionHandle : Set
ConnectionHandle = Nat

record ConnectionState : Set where
  constructor connection-state
  field
    component-name : String
    connections    : List ConnectionHandle
    binder         : Maybe BinderHandle
    dead           : Bool

data ConnectionEffect : Set where
  service-connected :
    ConnectionHandle → String → BinderHandle → ConnectionEffect
  service-disconnected :
    ConnectionHandle → String → ConnectionEffect
  link-to-death : BinderHandle → ConnectionEffect
  remove-from-cache : ConnectionEffect

connected-effects :
  String → BinderHandle → List ConnectionHandle → List ConnectionEffect
connected-effects component binder [] = []
connected-effects component binder (connection ∷ rest) =
  service-connected connection component binder ∷
  connected-effects component binder rest

disconnected-effects :
  String → List ConnectionHandle → List ConnectionEffect
disconnected-effects component [] = []
disconnected-effects component (connection ∷ rest) =
  service-disconnected connection component ∷
  disconnected-effects component rest

record Transition : Set where
  constructor transition
  field
    state   : ConnectionState
    effects : List ConnectionEffect

connected : BinderHandle → ConnectionState → Transition
connected binder state =
  transition
    (connection-state
      (ConnectionState.component-name state)
      (ConnectionState.connections state)
      (just binder)
      false)
    (link-to-death binder ∷
     connected-effects
       (ConnectionState.component-name state)
       binder
       (ConnectionState.connections state))

died : ConnectionState → Transition
died state with ConnectionState.dead state
... | true = transition state []
... | false =
  transition
    (connection-state
      (ConnectionState.component-name state)
      []
      nothing
      true)
    (disconnected-effects
       (ConnectionState.component-name state)
       (ConnectionState.connections state)
     ++ (remove-from-cache ∷ []))
  where
  _++_ : List ConnectionEffect → List ConnectionEffect → List ConnectionEffect
  [] ++ ys = ys
  (x ∷ xs) ++ ys = x ∷ (xs ++ ys)
