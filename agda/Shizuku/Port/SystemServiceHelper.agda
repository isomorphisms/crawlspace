{-# OPTIONS --safe #-}

module Shizuku.Port.SystemServiceHelper where

open import Agda.Builtin.Bool using (true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String; primStringEquality)

BinderHandle : Set
BinderHandle = Nat

record ServiceEntry : Set where
  constructor service-entry
  field
    name   : String
    binder : BinderHandle

find-service : String → List ServiceEntry → Maybe BinderHandle
find-service name [] = nothing
find-service name (entry ∷ rest)
  with primStringEquality name (ServiceEntry.name entry)
... | true = just (ServiceEntry.binder entry)
... | false = find-service name rest

cache-service :
  String → BinderHandle → List ServiceEntry → List ServiceEntry
cache-service name binder entries =
  service-entry name binder ∷ entries

record TransactionEntry : Set where
  constructor transaction-entry
  field
    class-name  : String
    method-name : String
    code        : Nat

find-transaction :
  String → String → List TransactionEntry → Maybe Nat
find-transaction class-name method-name [] = nothing
find-transaction class-name method-name (entry ∷ rest)
  with primStringEquality class-name (TransactionEntry.class-name entry)
... | false = find-transaction class-name method-name rest
... | true with primStringEquality method-name (TransactionEntry.method-name entry)
...   | true = just (TransactionEntry.code entry)
...   | false = find-transaction class-name method-name rest

data ObtainParcelResult : Set where
  direct-transact-unsupported : ObtainParcelResult

obtain-parcel : ObtainParcelResult
obtain-parcel = direct-transact-unsupported
