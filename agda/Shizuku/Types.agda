{-# OPTIONS --safe #-}

module Shizuku.Types where

open import Agda.Builtin.Bool using (Bool)
open import Agda.Builtin.List using (List)
open import Agda.Builtin.Maybe using (Maybe)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

Uid : Set
Uid = Nat

Pid : Set
Pid = Nat

UserId : Set
UserId = Nat

AppId : Set
AppId = Nat

ApiVersion : Set
ApiVersion = Nat

RequestCode : Set
RequestCode = Nat

Mask : Set
Mask = Nat

Flags : Set
Flags = Nat

Token : Set
Token = String

PackageName : Set
PackageName = String

ClassName : Set
ClassName = String

ProcessName : Set
ProcessName = String

PermissionName : Set
PermissionName = String

SELinuxContext : Set
SELinuxContext = String

record ClientId : Set where
  constructor mk-client-id
  field
    uid : Uid
    pid : Pid

data ServerIdentity : Set where
  shell : ServerIdentity
  root  : ServerIdentity

data Grant : Set where
  undecided : Grant
  denied    : Grant
  allowed   : Grant

record ClientRecord : Set where
  constructor client-record
  field
    identity     : ClientId
    package-name : PackageName
    api-version  : ApiVersion
    grant        : Grant

data ServiceLife : Set where
  starting : ServiceLife
  alive    : ServiceLife
  dead     : ServiceLife

record UserServiceKey : Set where
  constructor user-service-key
  field
    service-package : PackageName
    service-class   : ClassName
    service-tag     : Maybe String

record UserServiceRecord : Set where
  constructor user-service-record
  field
    key          : UserServiceKey
    token        : Token
    version-code : Nat
    daemon       : Bool
    life         : ServiceLife

record PermissionEntry : Set where
  constructor permission-entry
  field
    entry-uid   : Uid
    packages    : List PackageName
    entry-grant : Grant
