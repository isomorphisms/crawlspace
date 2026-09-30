{-# OPTIONS --safe #-}

module Shizuku.Manager.Provider where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String; primStringEquality)

BinderHandle : Set
BinderHandle = Nat

method-send-user-service : String
method-send-user-service = "sendUserService"

wait-timeout-seconds : Nat
wait-timeout-seconds = 5

record Request : Set where
  constructor service-request
  field
    token  : String
    binder : BinderHandle

data State : Set where
  waiting-for-shizuku : Request → State
  attached            : BinderHandle → State
  timed-out           : State
  failed              : State

data Effect : Set where
  add-sticky-binder-listener : Effect
  attach-user-service : String → BinderHandle → Effect
  return-server-binder : Effect
  remove-listener : Effect
  await-five-seconds : Effect

begin : Request → List Effect
begin request =
  add-sticky-binder-listener ∷
  await-five-seconds ∷ []

binder-received : Request → BinderHandle → List Effect
binder-received request server =
  attach-user-service
    (Request.token request)
    (Request.binder request)
  ∷ return-server-binder
  ∷ remove-listener
  ∷ []
