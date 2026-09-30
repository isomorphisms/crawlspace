{-# OPTIONS --safe #-}

module Shizuku.Port.UserServiceManager where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String; primStringEquality)

open import Shizuku.Port.Prelude
open import Shizuku.Port.UserServiceRecord

record ServiceKey : Set where
  constructor service-key
  field
    package-name : String
    class-name   : String
    tag-or-class : String

record ManagedService : Set where
  constructor managed-service
  field
    key    : ServiceKey
    service-record : UserServiceRecord

same-key : ServiceKey → ServiceKey → Bool
same-key a b =
  primStringEquality
    (ServiceKey.tag-or-class a)
    (ServiceKey.tag-or-class b)

find-service : ServiceKey → List ManagedService → Maybe ManagedService
find-service key [] = nothing
find-service key (service ∷ rest) with same-key key (ManagedService.key service)
... | true = just service
... | false = find-service key rest

remove-service : ServiceKey → List ManagedService → List ManagedService
remove-service key [] = []
remove-service key (service ∷ rest)
  with same-key key (ManagedService.key service)
... | true = rest
... | false = service ∷ remove-service key rest

data PeekResult : Set where
  legacy-no-service : PeekResult
  v13-no-service    : PeekResult
  legacy-found      : PeekResult
  v13-found         : Nat → PeekResult

peek-result :
  Nat → Maybe ManagedService → Bool → PeekResult
peek-result api-version nothing _ with 13 ≤ᵇ api-version
... | true = v13-no-service
... | false = legacy-no-service
peek-result api-version (just service) service-alive
  with service-alive
... | false with 13 ≤ᵇ api-version
...   | true = v13-no-service
...   | false = legacy-no-service
... | true with 13 ≤ᵇ api-version
...   | true =
      v13-found
        (UserServiceRecord.version-code (ManagedService.service-record service))
...   | false = legacy-found

record StartRequest : Set where
  constructor start-request
  field
    key                 : ServiceKey
    token               : String
    package-name        : String
    class-name          : String
    process-name-suffix : String
    calling-uid         : Nat
    use-32-bit          : Bool
    debug               : Bool

data ManagerEffect : Set where
  start-service : StartRequest → ManagerEffect
  broadcast-existing : String → ManagerEffect
  destroy-record : String → ManagerEffect

record AddPlan : Set where
  constructor add-plan
  field
    services : List ManagedService
    effects  : List ManagerEffect
    result   : PeekResult

record ExistingStatus : Set where
  constructor existing-status
  field
    binder-alive : Bool
    starting     : Bool

choose-existing :
  Nat →
  Bool →
  Maybe ManagedService →
  Maybe ExistingStatus →
  PeekResult
choose-existing api-version no-create service status with no-create
... | true with service
...   | nothing = peek-result api-version nothing false
...   | just existing with status
...     | nothing = peek-result api-version (just existing) false
...     | just s =
        peek-result api-version (just existing)
          (ExistingStatus.binder-alive s)
... | false = legacy-found

should-reuse :
  Nat → ManagedService → ExistingStatus → Bool
should-reuse requested-version service status =
  nat-eq requested-version
    (UserServiceRecord.version-code (ManagedService.service-record service))
  &&
  (ExistingStatus.starting status || ExistingStatus.binder-alive status)
