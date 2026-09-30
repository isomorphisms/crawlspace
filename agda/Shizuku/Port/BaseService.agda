{-# OPTIONS --safe #-}

module Shizuku.Port.BaseService where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat)

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

client-enforcement : Maybe ClientRecord → Enforcement
client-enforcement nothing = not-attached
client-enforcement (just client) with ClientRecord.allowed client
... | true = permission-ok
... | false = attached-but-denied

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
...   | false = client-enforcement client

enforce-manager-permission :
  ServerProcess → Caller → Bool → Bool
enforce-manager-permission server caller subclass-allows
  with nat-eq (Caller.pid caller) (ServerProcess.pid server)
... | true = true
... | false = subclass-allows

client-self-permission :
  Maybe ClientRecord → Result Bool RequireError
client-self-permission nothing = error not-attached
client-self-permission (just client) = ok (ClientRecord.allowed client)

check-self-permission :
  ServerProcess → Caller → Maybe ClientRecord → Result Bool RequireError
check-self-permission server caller client
  with nat-eq (Caller.uid caller) (ServerProcess.uid server)
     | nat-eq (Caller.pid caller) (ServerProcess.pid server)
... | true | _ = ok true
... | false | true = ok true
... | false | false = client-self-permission client

data RequestPermissionDecision : Set where
  ignore-self               : RequestPermissionDecision
  reply-already-allowed     : RequestPermissionDecision
  reply-persistently-denied : RequestPermissionDecision
  show-confirmation         : RequestPermissionDecision
  request-from-unattached   : RequestPermissionDecision

denied-request-decision :
  Maybe PackageEntry → RequestPermissionDecision
denied-request-decision nothing = show-confirmation
denied-request-decision (just entry) with is-denied entry
... | true = reply-persistently-denied
... | false = show-confirmation

client-request-decision :
  Maybe ClientRecord → Maybe PackageEntry → RequestPermissionDecision
client-request-decision nothing entry = request-from-unattached
client-request-decision (just client) entry with ClientRecord.allowed client
... | true = reply-already-allowed
... | false = denied-request-decision entry

request-permission :
  ServerProcess →
  Caller →
  Maybe ClientRecord →
  Maybe PackageEntry →
  RequestPermissionDecision
request-permission server caller client entry
  with nat-eq (Caller.uid caller) (ServerProcess.uid server)
     | nat-eq (Caller.pid caller) (ServerProcess.pid server)
... | true | _ = ignore-self
... | false | true = ignore-self
... | false | false = client-request-decision client entry

client-rationale :
  Maybe ClientRecord →
  Maybe PackageEntry →
  Result Bool RequireError
client-rationale nothing entry = error not-attached
client-rationale (just client) nothing = ok false
client-rationale (just client) (just entry) = ok (is-denied entry)

should-show-rationale :
  ServerProcess →
  Caller →
  Maybe ClientRecord →
  Maybe PackageEntry →
  Result Bool RequireError
should-show-rationale server caller client entry
  with nat-eq (Caller.uid caller) (ServerProcess.uid server)
     | nat-eq (Caller.pid caller) (ServerProcess.pid server)
... | true | _ = ok true
... | false | true = ok true
... | false | false = client-rationale client entry

BinderHandle : Set
BinderHandle = Nat

record RemoteTransaction : Set where
  constructor remote-transaction
  field
    target-binder       : BinderHandle
    target-code         : Nat
    outer-flags         : Nat
    embedded-flags      : Maybe Nat
    caller-api-version  : Maybe Nat

v13-flags : RemoteTransaction → Nat → Nat
v13-flags transaction api with 13 ≤ᵇ api
... | false = RemoteTransaction.outer-flags transaction
... | true with RemoteTransaction.embedded-flags transaction
...   | nothing = RemoteTransaction.outer-flags transaction
...   | just flags = flags

effective-target-flags : RemoteTransaction → Nat
effective-target-flags transaction
  with RemoteTransaction.caller-api-version transaction
... | nothing = RemoteTransaction.outer-flags transaction
... | just api = v13-flags transaction api

record NewProcessOwner : Set where
  constructor new-process-owner
  field
    owner-binder : Maybe ClientHandle

process-owner : Maybe ClientRecord → NewProcessOwner
process-owner nothing = new-process-owner nothing
process-owner (just client) =
  new-process-owner (just (ClientRecord.client client))

data SpecialTransaction : Set where
  remote-transact              : SpecialTransaction
  legacy-attach-application   : SpecialTransaction
  rish-transaction             : SpecialTransaction
  ordinary-binder-transaction : SpecialTransaction

classify-nonremote : Nat → Bool → SpecialTransaction
classify-nonremote code handled-by-rish with nat-eq code 14
... | true = legacy-attach-application
... | false with handled-by-rish
...   | true = rish-transaction
...   | false = ordinary-binder-transaction

classify-transaction :
  Nat → Nat → Bool → SpecialTransaction
classify-transaction code remote-code handled-by-rish
  with nat-eq code remote-code
... | true = remote-transact
... | false = classify-nonremote code handled-by-rish
