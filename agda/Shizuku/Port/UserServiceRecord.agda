{-# OPTIONS --safe #-}

module Shizuku.Port.UserServiceRecord where

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

record UserServiceRecord : Set where
  constructor user-service-record
  field
    version-code : Nat
    token        : String
    service      : Maybe BinderHandle
    callbacks    : List ConnectionHandle
    daemon       : Bool
    starting     : Bool

data RecordEffect : Set where
  schedule-start-timeout : String → Nat → RecordEffect
  cancel-start-timeout   : String → RecordEffect
  link-service-death     : BinderHandle → String → RecordEffect
  unlink-service-death   : BinderHandle → String → RecordEffect
  callback-connected     : ConnectionHandle → BinderHandle → RecordEffect
  callback-died          : ConnectionHandle → RecordEffect
  transact-destroy       : BinderHandle → RecordEffect
  kill-callbacks         : String → RecordEffect
  remove-self            : String → RecordEffect

record Transition : Set where
  constructor transition
  field
    state   : UserServiceRecord
    effects : List RecordEffect

set-starting-timeout : Nat → UserServiceRecord → Transition
set-starting-timeout timeout r with UserServiceRecord.starting r
... | true = transition r []
... | false =
  transition
    (user-service-record
      (UserServiceRecord.version-code r)
      (UserServiceRecord.token r)
      (UserServiceRecord.service r)
      (UserServiceRecord.callbacks r)
      (UserServiceRecord.daemon r)
      true)
    (schedule-start-timeout (UserServiceRecord.token r) timeout ∷ [])

set-daemon : Bool → UserServiceRecord → UserServiceRecord
set-daemon daemon r =
  user-service-record
    (UserServiceRecord.version-code r)
    (UserServiceRecord.token r)
    (UserServiceRecord.service r)
    (UserServiceRecord.callbacks r)
    daemon
    (UserServiceRecord.starting r)

connected-effects :
  BinderHandle → List ConnectionHandle → List RecordEffect
connected-effects binder [] = []
connected-effects binder (connection ∷ rest) =
  callback-connected connection binder ∷ connected-effects binder rest

died-effects : List ConnectionHandle → List RecordEffect
died-effects [] = []
died-effects (connection ∷ rest) =
  callback-died connection ∷ died-effects rest

set-binder : BinderHandle → UserServiceRecord → Transition
set-binder binder r =
  transition
    (user-service-record
      (UserServiceRecord.version-code r)
      (UserServiceRecord.token r)
      (just binder)
      (UserServiceRecord.callbacks r)
      (UserServiceRecord.daemon r)
      false)
    (cancel-start-timeout (UserServiceRecord.token r) ∷
     link-service-death binder (UserServiceRecord.token r) ∷
     connected-effects binder (UserServiceRecord.callbacks r))

callback-died-transition : Nat → UserServiceRecord → Transition
callback-died-transition remaining r
  with UserServiceRecord.daemon r
... | true = transition r []
... | false with nat-eq remaining 0
...   | false = transition r []
...   | true =
      transition record (remove-self (UserServiceRecord.token r) ∷ [])

service-died : UserServiceRecord → Transition
service-died r =
  transition record (remove-self (UserServiceRecord.token r) ∷ [])

broadcast-died : UserServiceRecord → List RecordEffect
broadcast-died r = died-effects (UserServiceRecord.callbacks r)

destroy-effects : UserServiceRecord → List RecordEffect
destroy-effects r with UserServiceRecord.service r
... | nothing =
  kill-callbacks (UserServiceRecord.token r) ∷ []
... | just binder =
  unlink-service-death binder (UserServiceRecord.token r) ∷
  transact-destroy binder ∷
  kill-callbacks (UserServiceRecord.token r) ∷ []
