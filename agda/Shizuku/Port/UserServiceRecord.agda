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
set-starting-timeout timeout record with UserServiceRecord.starting record
... | true = transition record []
... | false =
  transition
    (user-service-record
      (UserServiceRecord.version-code record)
      (UserServiceRecord.token record)
      (UserServiceRecord.service record)
      (UserServiceRecord.callbacks record)
      (UserServiceRecord.daemon record)
      true)
    (schedule-start-timeout (UserServiceRecord.token record) timeout ∷ [])

set-daemon : Bool → UserServiceRecord → UserServiceRecord
set-daemon daemon record =
  user-service-record
    (UserServiceRecord.version-code record)
    (UserServiceRecord.token record)
    (UserServiceRecord.service record)
    (UserServiceRecord.callbacks record)
    daemon
    (UserServiceRecord.starting record)

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
set-binder binder record =
  transition
    (user-service-record
      (UserServiceRecord.version-code record)
      (UserServiceRecord.token record)
      (just binder)
      (UserServiceRecord.callbacks record)
      (UserServiceRecord.daemon record)
      false)
    (cancel-start-timeout (UserServiceRecord.token record) ∷
     link-service-death binder (UserServiceRecord.token record) ∷
     connected-effects binder (UserServiceRecord.callbacks record))

callback-died-transition : Nat → UserServiceRecord → Transition
callback-died-transition remaining record
  with UserServiceRecord.daemon record
... | true = transition record []
... | false with nat-eq remaining 0
...   | false = transition record []
...   | true =
      transition record (remove-self (UserServiceRecord.token record) ∷ [])

service-died : UserServiceRecord → Transition
service-died record =
  transition record (remove-self (UserServiceRecord.token record) ∷ [])

broadcast-died : UserServiceRecord → List RecordEffect
broadcast-died record = died-effects (UserServiceRecord.callbacks record)

destroy-effects : UserServiceRecord → List RecordEffect
destroy-effects record with UserServiceRecord.service record
... | nothing =
  kill-callbacks (UserServiceRecord.token record) ∷ []
... | just binder =
  unlink-service-death binder (UserServiceRecord.token record) ∷
  transact-destroy binder ∷
  kill-callbacks (UserServiceRecord.token record) ∷ []
