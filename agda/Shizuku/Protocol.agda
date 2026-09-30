{-# OPTIONS --safe #-}

module Shizuku.Protocol where

open import Agda.Builtin.Bool using (Bool)
open import Agda.Builtin.List using (List)
open import Agda.Builtin.Maybe using (Maybe)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

open import Shizuku.Types

record ProcessSpec : Set where
  constructor process-spec
  field
    command     : List String
    environment : Maybe (List String)
    directory   : Maybe String

record AttachApplicationArgs : Set where
  constructor attach-application-args
  field
    caller          : ClientId
    requested-package : PackageName
    requested-api     : ApiVersion

record UserServiceSpec : Set where
  constructor user-service-spec
  field
    service-key  : UserServiceKey
    version-code : Nat
    daemon       : Bool
    no-create    : Bool
    use-32-bit   : Bool
    debuggable   : Bool

data Persistence : Set where
  one-time   : Persistence
  persistent : Persistence

record PermissionResult : Set where
  constructor permission-result
  field
    target-uid   : Uid
    target-pid   : Pid
    request-code : RequestCode
    result-grant : Grant
    persistence  : Persistence
    packages     : List PackageName

data Call : Set where
  get-version                         : Call
  get-uid                             : Call
  check-permission                    : PermissionName → Call
  new-process                         : ProcessSpec → Call
  get-selinux-context                 : Call
  get-system-property                 : String → String → Call
  set-system-property                 : String → String → Call
  add-user-service                    : UserServiceSpec → Call
  remove-user-service                 : UserServiceKey → Call
  request-permission                  : RequestCode → Call
  check-self-permission               : Call
  should-show-permission-rationale    : Call
  attach-application                  : AttachApplicationArgs → Call
  exit                                : Call
  attach-user-service                 : Token → Call
  dispatch-package-changed            : PackageName → Call
  is-hidden                           : Uid → Call
  dispatch-permission-result          : PermissionResult → Call
  get-flags-for-uid                   : Uid → Mask → Call
  update-flags-for-uid                : Uid → Mask → Flags → Call

transaction-code : Call → Nat
transaction-code get-version                              = 2
transaction-code get-uid                                  = 3
transaction-code (check-permission _)                     = 4
transaction-code (new-process _)                          = 7
transaction-code get-selinux-context                      = 8
transaction-code (get-system-property _ _)                = 9
transaction-code (set-system-property _ _)                = 10
transaction-code (add-user-service _)                     = 11
transaction-code (remove-user-service _)                  = 12
transaction-code (request-permission _)                   = 14
transaction-code check-self-permission                    = 15
transaction-code should-show-permission-rationale         = 16
transaction-code (attach-application _)                   = 17
transaction-code exit                                     = 100
transaction-code (attach-user-service _)                  = 101
transaction-code (dispatch-package-changed _)             = 102
transaction-code (is-hidden _)                            = 103
transaction-code (dispatch-permission-result _)           = 104
transaction-code (get-flags-for-uid _ _)                  = 105
transaction-code (update-flags-for-uid _ _ _)             = 106
