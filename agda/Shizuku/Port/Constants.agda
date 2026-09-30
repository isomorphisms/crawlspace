{-# OPTIONS --safe #-}

module Shizuku.Port.Constants where

open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

server-version : Nat
server-version = 13

server-patch-version : Nat
server-patch-version = 6

binder-descriptor : String
binder-descriptor = "moe.shizuku.server.IShizukuService"

binder-transaction-transact : Nat
binder-transaction-transact = 1

user-service-transaction-destroy : Nat
user-service-transaction-destroy = 16777115

flag-allowed : Nat
flag-allowed = 2

flag-denied : Nat
flag-denied = 4

mask-permission : Nat
mask-permission = 6

manager-app-not-found : Nat
manager-app-not-found = 50

permission : String
permission = "moe.shizuku.manager.permission.API_V23"

manager-permission : String
manager-permission = "moe.shizuku.manager.permission.MANAGER"

manager-application-id : String
manager-application-id = "moe.shizuku.privileged.api"

request-permission-action : String
request-permission-action =
  "moe.shizuku.privileged.api.intent.action.REQUEST_PERMISSION"

binder-transaction-get-applications : Nat
binder-transaction-get-applications = 10001

extra-binder : String
extra-binder = "moe.shizuku.privileged.api.intent.extra.BINDER"

user-service-arg-tag : String
user-service-arg-tag = "shizuku:user-service-arg-tag"

user-service-arg-component : String
user-service-arg-component = "shizuku:user-service-arg-component"

user-service-arg-debuggable : String
user-service-arg-debuggable = "shizuku:user-service-arg-debuggable"

user-service-arg-version-code : String
user-service-arg-version-code = "shizuku:user-service-arg-version-code"

user-service-arg-process-name : String
user-service-arg-process-name = "shizuku:user-service-arg-process-name"

user-service-arg-no-create : String
user-service-arg-no-create = "shizuku:user-service-arg-no-create"

user-service-arg-daemon : String
user-service-arg-daemon = "shizuku:user-service-arg-daemon"

user-service-arg-use-32-bit : String
user-service-arg-use-32-bit =
  "shizuku:user-service-arg-use-32-bit-app-process"

user-service-arg-remove : String
user-service-arg-remove = "shizuku:user-service-remove"

user-service-arg-token : String
user-service-arg-token = "shizuku:user-service-arg-token"
