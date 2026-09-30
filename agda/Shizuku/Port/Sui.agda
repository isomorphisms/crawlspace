{-# OPTIONS --safe #-}

module Shizuku.Port.Sui where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

BinderHandle : Set
BinderHandle = Nat

bridge-transaction-code : Nat
bridge-transaction-code = 1599296841

bridge-service-descriptor : String
bridge-service-descriptor = "android.app.IActivityManager"

bridge-service-name : String
bridge-service-name = "activity"

bridge-action-get-binder : Nat
bridge-action-get-binder = 2

record State : Set where
  constructor sui-state
  field
    is-sui : Bool

initial : State
initial = sui-state false

record InitResult : Set where
  constructor init-result
  field
    state  : State
    binder : Maybe BinderHandle

init : Maybe BinderHandle → InitResult
init nothing = init-result (sui-state false) nothing
init (just binder) = init-result (sui-state true) (just binder)
