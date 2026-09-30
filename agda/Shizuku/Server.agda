{-# OPTIONS --safe #-}

module Shizuku.Server where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Nat using (Nat; zero; suc)
open import Agda.Builtin.String using (primStringEquality)

open import Shizuku.Types
open import Shizuku.Protocol

record ServerState : Set where
  constructor server-state
  field
    server-identity : ServerIdentity
    clients         : List ClientRecord
    services        : List UserServiceRecord
    permissions     : List PermissionEntry

empty-state : ServerIdentity → ServerState
empty-state who = server-state who [] [] []

nat-eq : Nat → Nat → Bool
nat-eq zero zero       = true
nat-eq zero (suc _)    = false
nat-eq (suc _) zero    = false
nat-eq (suc n) (suc m) = nat-eq n m

not : Bool → Bool
not true  = false
not false = true

filter-list : {A : Set} → (A → Bool) → List A → List A
filter-list keep [] = []
filter-list keep (x ∷ xs) with keep x
... | true  = x ∷ filter-list keep xs
... | false = filter-list keep xs

client-uid : ClientRecord → Uid
client-uid client = ClientId.uid (ClientRecord.identity client)

set-client-grant : Grant → ClientRecord → ClientRecord
set-client-grant grant (client-record identity package-name api-version _) =
  client-record identity package-name api-version grant

update-client-grants : Uid → Grant → List ClientRecord → List ClientRecord
update-client-grants uid grant [] = []
update-client-grants uid grant (client ∷ rest) with nat-eq uid (client-uid client)
... | true  = set-client-grant grant client ∷ update-client-grants uid grant rest
... | false = client ∷ update-client-grants uid grant rest

set-permission-entry :
  Uid → List PackageName → Grant → List PermissionEntry → List PermissionEntry
set-permission-entry uid packages grant [] =
  permission-entry uid packages grant ∷ []
set-permission-entry uid packages grant (entry ∷ rest)
  with nat-eq uid (PermissionEntry.entry-uid entry)
... | true  = permission-entry uid packages grant ∷ rest
... | false = entry ∷ set-permission-entry uid packages grant rest

attach-client : ClientRecord → ServerState → ServerState
attach-client client state =
  server-state
    (ServerState.server-identity state)
    (client ∷ ServerState.clients state)
    (ServerState.services state)
    (ServerState.permissions state)

record-permission : PermissionResult → ServerState → ServerState
record-permission result state with PermissionResult.persistence result
... | one-time =
  server-state
    (ServerState.server-identity state)
    (update-client-grants
      (PermissionResult.target-uid result)
      (PermissionResult.result-grant result)
      (ServerState.clients state))
    (ServerState.services state)
    (ServerState.permissions state)
... | persistent =
  server-state
    (ServerState.server-identity state)
    (update-client-grants
      (PermissionResult.target-uid result)
      (PermissionResult.result-grant result)
      (ServerState.clients state))
    (ServerState.services state)
    (set-permission-entry
      (PermissionResult.target-uid result)
      (PermissionResult.packages result)
      (PermissionResult.result-grant result)
      (ServerState.permissions state))

attach-user-service : UserServiceRecord → ServerState → ServerState
attach-user-service service state =
  server-state
    (ServerState.server-identity state)
    (ServerState.clients state)
    (service ∷ ServerState.services state)
    (ServerState.permissions state)

keep-service-for-package : PackageName → UserServiceRecord → Bool
keep-service-for-package package-name service =
  not
    (primStringEquality
      package-name
      (UserServiceKey.service-package (UserServiceRecord.key service)))

remove-services-for-package : PackageName → ServerState → ServerState
remove-services-for-package package-name state =
  server-state
    (ServerState.server-identity state)
    (ServerState.clients state)
    (filter-list
      (keep-service-for-package package-name)
      (ServerState.services state))
    (ServerState.permissions state)

remove-services-for-packages :
  List PackageName → ServerState → ServerState
remove-services-for-packages [] state = state
remove-services-for-packages (package-name ∷ rest) state =
  remove-services-for-packages rest
    (remove-services-for-package package-name state)

set-service-life : ServiceLife → UserServiceRecord → UserServiceRecord
set-service-life life
  (user-service-record key token version-code daemon _) =
  user-service-record key token version-code daemon life

mark-service-dead-in-list :
  Token → List UserServiceRecord → List UserServiceRecord
mark-service-dead-in-list token [] = []
mark-service-dead-in-list token (service ∷ rest)
  with primStringEquality token (UserServiceRecord.token service)
... | true  =
  set-service-life dead service ∷ mark-service-dead-in-list token rest
... | false =
  service ∷ mark-service-dead-in-list token rest

mark-service-dead : Token → ServerState → ServerState
mark-service-dead token state =
  server-state
    (ServerState.server-identity state)
    (ServerState.clients state)
    (mark-service-dead-in-list token (ServerState.services state))
    (ServerState.permissions state)
