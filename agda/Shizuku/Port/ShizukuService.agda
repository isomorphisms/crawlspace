{-# OPTIONS --safe #-}

module Shizuku.Port.ShizukuService where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String; primStringEquality)

open import Shizuku.Port.Prelude
open import Shizuku.Port.Constants
open import Shizuku.Port.ConfigManager
open import Shizuku.Port.ClientManager

record CallerFacts : Set where
  constructor caller-facts
  field
    caller-app-id             : Nat
    manager-app-id            : Nat
    same-server-uid           : Bool
    attached-client           : Maybe ClientRecord
    manifest-permission-granted : Bool

manager-caller : CallerFacts → Bool
manager-caller facts =
  nat-eq
    (CallerFacts.caller-app-id facts)
    (CallerFacts.manager-app-id facts)

caller-privileged : CallerFacts → Bool
caller-privileged facts with CallerFacts.same-server-uid facts
... | true = true
... | false with manager-caller facts
...   | true = true
...   | false with CallerFacts.attached-client facts
...     | just client = ClientRecord.allowed client
...     | nothing = CallerFacts.manifest-permission-granted facts

data RequestedApi : Set where
  pre-v13-attach : RequestedApi
  api-version     : Nat → RequestedApi

reply-server-version : RequestedApi → Nat
reply-server-version pre-v13-attach = 12
reply-server-version (api-version _) = server-version

record AttachRequest : Set where
  constructor attach-request
  field
    uid               : Nat
    pid               : Nat
    client-handle     : ClientHandle
    requested-package : String
    requested-api     : RequestedApi
    uid-packages      : List String

data AttachError : Set where
  package-not-owned : AttachError

record AttachReply : Set where
  constructor attach-reply
  field
    server-uid      : Nat
    version         : Nat
    patch-version   : Nat
    selinux-context : String
    manager         : Bool
    allowed         : Bool
    show-rationale  : Bool

api-number : RequestedApi → Nat
api-number pre-v13-attach = 12
api-number (api-version n) = n

prepare-attach :
  Nat →
  String →
  List PackageEntry →
  AttachRequest →
  Result ClientRecord AttachError
prepare-attach server-uid context config request
  with member-string
    (AttachRequest.requested-package request)
    (AttachRequest.uid-packages request)
... | false = error package-not-owned
... | true =
  ok
    (make-client
      (AttachRequest.uid request)
      (AttachRequest.pid request)
      (AttachRequest.client-handle request)
      (AttachRequest.requested-package request)
      (api-number (AttachRequest.requested-api request))
      config)

make-attach-reply :
  Nat → String → AttachRequest → ClientRecord → AttachReply
make-attach-reply server-uid context request client =
  attach-reply
    server-uid
    (reply-server-version (AttachRequest.requested-api request))
    server-patch-version
    context
    (primStringEquality
      (AttachRequest.requested-package request)
      manager-application-id)
    (ClientRecord.allowed client)
    false

record ConfirmationFacts : Set where
  constructor confirmation-facts
  field
    application-info-present : Bool
    manager-present          : Bool
    work-profile             : Bool
    requested-user-id        : Nat

data ConfirmationDecision : Set where
  no-confirmation         : ConfirmationDecision
  reject-permission       : ConfirmationDecision
  start-confirmation      : Nat → ConfirmationDecision

confirmation-decision : ConfirmationFacts → ConfirmationDecision
confirmation-decision facts with ConfirmationFacts.application-info-present facts
... | false = no-confirmation
... | true with ConfirmationFacts.manager-present facts
...   | true with ConfirmationFacts.work-profile facts
...     | true = start-confirmation 0
...     | false =
        start-confirmation (ConfirmationFacts.requested-user-id facts)
...   | false with ConfirmationFacts.work-profile facts
...     | true = start-confirmation 0
...     | false = reject-permission

set-uid-allowed : Nat → Bool → List ClientRecord → List ClientRecord
set-uid-allowed uid allowed [] = []
set-uid-allowed uid allowed (client ∷ rest)
  with nat-eq uid (ClientRecord.uid client)
... | true =
  set-allowed allowed client ∷ set-uid-allowed uid allowed rest
... | false = client ∷ set-uid-allowed uid allowed rest

packages-for-uid : Nat → List ClientRecord → List String
packages-for-uid uid [] = []
packages-for-uid uid (client ∷ rest)
  with nat-eq uid (ClientRecord.uid client)
... | true =
  append-unique-string
    (packages-for-uid uid rest)
    (ClientRecord.package-name client)
... | false = packages-for-uid uid rest

data PermissionEffect : Set where
  dispatch-result : Nat → Nat → Bool → PermissionEffect
  persist-config  : Nat → List String → PermissionFlags → PermissionEffect
  grant-api-runtime-permission : String → Nat → PermissionEffect
  revoke-api-runtime-permission : String → Nat → PermissionEffect
  force-stop      : String → Nat → PermissionEffect
  remove-user-services : String → PermissionEffect

record PermissionTransition : Set where
  constructor permission-transition
  field
    clients : List ClientRecord
    config  : List PackageEntry
    effects : List PermissionEffect

notify-target :
  Nat → Nat → Nat → Bool → List ClientRecord → List PermissionEffect
notify-target uid pid request-code allowed [] = []
notify-target uid pid request-code allowed (client ∷ rest)
  with nat-eq uid (ClientRecord.uid client)
... | false = notify-target uid pid request-code allowed rest
... | true with nat-eq pid (ClientRecord.pid client)
...   | true =
      dispatch-result pid request-code allowed ∷
      notify-target uid pid request-code allowed rest
...   | false = notify-target uid pid request-code allowed rest

grant-effects : Nat → List String → List PermissionEffect
grant-effects user-id [] = []
grant-effects user-id (package-name ∷ rest) =
  grant-api-runtime-permission package-name user-id ∷
  grant-effects user-id rest

dispatch-permission-result :
  Nat →
  Nat →
  Nat →
  Nat →
  Bool →
  Bool →
  List String →
  List ClientRecord →
  List PackageEntry →
  PermissionTransition
dispatch-permission-result
  uid pid request-code user-id allowed one-time installed-api-packages clients config =
  permission-transition new-clients new-config
    (notify-target uid pid request-code allowed clients ++ persistence-effects)
  where
  new-clients : List ClientRecord
  new-clients = set-uid-allowed uid allowed clients

  value : PermissionFlags
  value with allowed
  ... | true = permission-flags true false
  ... | false = permission-flags false true

  package-names : List String
  package-names = packages-for-uid uid clients

  new-config : List PackageEntry
  new-config with one-time
  ... | true = config
  ... | false =
      update uid package-names permission-mask-all value config

  persistence-effects : List PermissionEffect
  persistence-effects with one-time
  ... | true = []
  ... | false with allowed
  ...   | false = persist-config uid package-names value ∷ []
  ...   | true =
      persist-config uid package-names value ∷
      grant-effects user-id installed-api-packages

  _++_ : List PermissionEffect → List PermissionEffect → List PermissionEffect
  [] ++ ys = ys
  (x ∷ xs) ++ ys = x ∷ (xs ++ ys)

revocation-effects : Nat → List ClientRecord → List PermissionEffect
revocation-effects uid [] = []
revocation-effects uid (client ∷ rest)
  with nat-eq uid (ClientRecord.uid client)
... | false = revocation-effects uid rest
... | true =
  force-stop (ClientRecord.package-name client) uid ∷
  remove-user-services (ClientRecord.package-name client) ∷
  revocation-effects uid rest

runtime-permission-effects :
  Bool → Nat → List String → List PermissionEffect
runtime-permission-effects allowed user-id [] = []
runtime-permission-effects allowed user-id (package-name ∷ rest)
  with allowed
... | true =
  grant-api-runtime-permission package-name user-id ∷
  runtime-permission-effects allowed user-id rest
... | false =
  revoke-api-runtime-permission package-name user-id ∷
  runtime-permission-effects allowed user-id rest
