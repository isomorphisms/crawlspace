{-# OPTIONS --safe #-}

module Shizuku.Manager.Adb.PairingService where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

data Action : Set where
  start-action : Action
  reply-action : String → Nat → Action
  stop-action  : Action
  unknown-action : Action

data State : Set where
  idle      : State
  searching : State
  awaiting-code : Nat → State
  pairing   : Nat → State
  finished  : Bool → State

data Failure : Set where
  cannot-connect : Failure
  invalid-code   : Failure
  key-store-error : Failure
  other-error    : Failure

data Effect : Set where
  start-mdns-pairing : Effect
  stop-mdns          : Effect
  show-searching     : Effect
  show-code-input    : Nat → Effect
  run-pairing-client : String → Nat → Effect
  show-working       : Effect
  show-success       : Effect
  show-failure       : Failure → Effect
  stop-service       : Effect
  remove-foreground  : Effect

record Transition : Set where
  constructor transition
  field
    state   : State
    effects : List Effect

handle : Action → Transition
handle start-action =
  transition searching (start-mdns-pairing ∷ show-searching ∷ [])
handle (reply-action code port) =
  transition (pairing port)
    (run-pairing-client code port ∷ show-working ∷ [])
handle stop-action =
  transition idle
    (remove-foreground ∷ stop-mdns ∷ stop-service ∷ [])
handle unknown-action = transition idle []

service-found : Nat → Transition
service-found port =
  transition (awaiting-code port) (show-code-input port ∷ [])

pairing-result : Bool → Failure → Transition
pairing-result true failure =
  transition (finished true)
    (remove-foreground ∷ show-success ∷ stop-mdns ∷ stop-service ∷ [])
pairing-result false failure =
  transition (finished false)
    (remove-foreground ∷ show-failure failure ∷ stop-service ∷ [])
