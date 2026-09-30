{-# OPTIONS --safe #-}

module Shizuku.Port.ClientManager where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

open import Shizuku.Port.Prelude
open import Shizuku.Port.ConfigManager

ClientHandle : Set
ClientHandle = Nat

record ClientRecord : Set where
  constructor client-record
  field
    uid          : Nat
    pid          : Nat
    client       : ClientHandle
    package-name : String
    api-version  : Nat
    allowed      : Bool

find-clients : Nat → List ClientRecord → List ClientRecord
find-clients uid [] = []
find-clients uid (client ∷ rest) with nat-eq uid (ClientRecord.uid client)
... | true = client ∷ find-clients uid rest
... | false = find-clients uid rest

find-client : Nat → Nat → List ClientRecord → Maybe ClientRecord
find-client uid pid [] = nothing
find-client uid pid (client ∷ rest)
  with nat-eq uid (ClientRecord.uid client)
... | false = find-client uid pid rest
... | true with nat-eq pid (ClientRecord.pid client)
...   | true = just client
...   | false = find-client uid pid rest

data RequireError : Set where
  not-attached : RequireError
  no-permission : RequireError

require-client :
  Nat → Nat → Bool → List ClientRecord → Result ClientRecord RequireError
require-client uid pid requires-permission clients
  with find-client uid pid clients
... | nothing = error not-attached
... | just client with requires-permission && not (ClientRecord.allowed client)
...   | true = error no-permission
...   | false = ok client

initially-allowed : Nat → List PackageEntry → Bool
initially-allowed uid config with find uid config
... | nothing = false
... | just entry = is-allowed entry

make-client :
  Nat → Nat → ClientHandle → String → Nat → List PackageEntry → ClientRecord
make-client uid pid client package-name api-version config =
  client-record
    uid pid client package-name api-version
    (initially-allowed uid config)

remove-client : Nat → Nat → List ClientRecord → List ClientRecord
remove-client uid pid [] = []
remove-client uid pid (client ∷ rest)
  with nat-eq uid (ClientRecord.uid client)
... | false = client ∷ remove-client uid pid rest
... | true with nat-eq pid (ClientRecord.pid client)
...   | true = rest
...   | false = client ∷ remove-client uid pid rest

set-allowed : Bool → ClientRecord → ClientRecord
set-allowed allowed client =
  client-record
    (ClientRecord.uid client)
    (ClientRecord.pid client)
    (ClientRecord.client client)
    (ClientRecord.package-name client)
    (ClientRecord.api-version client)
    allowed
