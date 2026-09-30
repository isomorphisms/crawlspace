{-# OPTIONS --safe #-}

module Shizuku.Port.AIDL where

open import Agda.Builtin.Bool using (Bool)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

BinderHandle : Set
BinderHandle = Nat

FileDescriptorHandle : Set
FileDescriptorHandle = Nat

data RemoteProcessCall : Set where
  get-output-stream : RemoteProcessCall
  get-input-stream  : RemoteProcessCall
  get-error-stream  : RemoteProcessCall
  wait-for          : RemoteProcessCall
  exit-value        : RemoteProcessCall
  destroy           : RemoteProcessCall
  alive             : RemoteProcessCall
  wait-for-timeout  : Nat → String → RemoteProcessCall

data ApplicationCall : Set where
  bind-application : ApplicationCall
  dispatch-request-permission-result : Nat → Bool → ApplicationCall
  show-permission-confirmation :
    Nat → Nat → String → Nat → ApplicationCall

data ServiceConnectionCall : Set where
  connected : BinderHandle → ServiceConnectionCall
  died      : ServiceConnectionCall

application-transaction-code : ApplicationCall → Nat
application-transaction-code bind-application = 1
application-transaction-code (dispatch-request-permission-result _ _) = 2
application-transaction-code (show-permission-confirmation _ _ _ _) = 10000
