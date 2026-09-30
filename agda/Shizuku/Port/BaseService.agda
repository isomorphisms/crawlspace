{-# OPTIONS --safe #-}

module Shizuku.Port.BaseService where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

open import Shizuku.Port.Prelude
open import Shizuku.Port.ClientManager
open import Shizuku.Port.ConfigManager

record Caller : Set where
  constructor caller
  field
    uid : Nat
    pid : Nat

record ServerProcess : Set where
  constructor server-process
  field
    uid : Nat
    pid : Nat

data Enforcement : Set where
  permission-ok         : Enforcement
  not-attached          : Enforcement
  attached-but-denied   : Enforcement

enforce-calling-permission :
  ServerProcess →
  Caller →
  Bool →
  Maybe ClientRecord →
  Enforcement
enforce-calling-permission server caller subclass-allows client
  with nat-eq (Caller.uid caller) (ServerProcess.uid server)
... | true = permission-ok
... | false with subclass-allows
...   | true = permission-ok
...   | false with client
...     | nothing = not-attached
...     | just attached with ClientRecord.allowed attached
...       | true = permission-ok
...       | false = attached-but-denied

enforce-manager-permission :
  ServerProcess → Caller → Bool → Bool
enforce-manager-permission server caller subclass-allows
  with nat-eq (Caller.pid caller) (ServerProcess.pid server)
... | true = true
... | false = subclass-allows

check-self-permission :
  ServerProcess → Caller → Maybe ClientRecord → Result Bool RequireError
check-self-permission server caller client
  with nat-eq (Caller.uid caller) (ServerProcess.uid server)
... | true = ok true
... | false with nat-eq (Caller.pid caller) (ServerProcess.pid server)
...   | true = ok true
...   | false with client
...     | nothing = error not-attached
...     | just attached = ok (ClientRecord.allowed attached)

data RequestPermissionDecision : Set where
  ignore-self              : RequestPermissionDecision
  reply-already-allowed    : RequestPermissionDecision
  reply-persistently-denied : RequestPermissionDecision
  show-confirmation        : RequestPermissionDecision
  request-from-unattached  : RequestPermissionDecision

request-permission :
  ServerProcess →
  Caller →
  Maybe ClientRecord →
  Maybe PackageEntry →
  RequestPermissionDecision
request-permission server caller client entry
  with nat-eq (Caller.uid caller) (ServerProcess.uid server)
... | true = ignore-self
... | false with nat-eq (Caller.pid caller) (ServerProcess.pid server)
...   | true = ignore-self
...   | false with client
...     | nothing = request-from-unattached
...     | just attached with ClientRecord.allowed attached
...       | true = reply-already-allowed
...       | false with entry
...         | just config-entry with is-denied config-entry
...           | true = reply-persistently-denied
...           | false = show-confirmation
...         | nothing = show-confirmation

should-show-rationale :
  ServerProcess →
  Caller →
  Maybe ClientRecord →
  Maybe PackageEntry →
  Result Bool RequireError
should-show-rationale server caller client entry
  with nat-eq (Caller.uid caller) (ServerProcess.uid server)
... | true = ok true
... | false with nat-eq (Caller.pid caller) (ServerProcess.pid server)
...   | true = ok true
...   | false with client
...     | nothing = error not-attached
...     | just attached with entry
...       | nothing = ok false
...       | just config-entry = ok (is-denied config-entry)

BinderHandle : Set
BinderHandle = Nat

record RemoteTransaction : Set where
  constructor remote-transaction
  field
    target-binder : BinderHandle
    target-code   : Nat
    outer-flags   : Nat
    embedded-flags : Maybe Nat
    caller-api-version : Maybe Nat

effective-target-flags : RemoteTransaction → Nat
effective-target-flags transaction
  with RemoteTransaction.caller-api-version transaction
... | nothing = RemoteTransaction.outer-flags transaction
... | just api with 13 ≤ᵇ api
...   | false = RemoteTransaction.outer-flags transaction
...   | true with RemoteTransaction.embedded-flags transaction
...     | nothing = RemoteTransaction.outer-flags transaction
...     | just flags = flags

record NewProcessOwner : Set where
  constructor new-process-owner
  field
    owner-binder : Maybe ClientHandle

process-owner : Maybe ClientRecord → NewProcessOwner
process-owner nothing = new-process-owner nothing
process-owner (just client) =
  new-process-owner (just (ClientRecord.client client))

data SpecialTransaction : Set where
  remote-transact : SpecialTransaction
  legacy-attach-application : SpecialTransaction
  rish-transaction : SpecialTransaction
  ordinary-binder-transaction : SpecialTransaction

classify-transaction :
  Nat → Nat → Bool → SpecialTransaction
classify-transaction code remote-code handled-by-rish
  with nat-eq code remote-code
... | true = remote-transact
... | false with nat-eq code 14
...   | true = legacy-attach-application
...   | false with handled-by-rish
...     | true = rish-transaction
...     | false = ordinary-binder-transaction
