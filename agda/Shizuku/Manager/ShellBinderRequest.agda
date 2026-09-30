{-# OPTIONS --safe #-}

module Shizuku.Manager.ShellBinderRequest where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String; primStringEquality)

BinderHandle : Set
BinderHandle = Nat

request-action : String
request-action = "rikka.shizuku.intent.action.REQUEST_BINDER"

record Request : Set where
  constructor request
  field
    action          : String
    receiver-binder : Maybe BinderHandle
    server-binder   : Maybe BinderHandle
    manager-apk     : String

data Decision : Set where
  ignore : Decision
  transact-reply : BinderHandle → Maybe BinderHandle → String → Decision

handle : Request → Decision
handle request with primStringEquality (Request.action request) request-action
... | false = ignore
... | true with Request.receiver-binder request
...   | nothing = ignore
...   | just receiver =
      transact-reply receiver
        (Request.server-binder request)
        (Request.manager-apk request)

reply-transaction-code : Nat
reply-transaction-code = 1
