{-# OPTIONS --safe #-}

module Shizuku.Port.ConfigManager where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

open import Shizuku.Port.Prelude

record PermissionFlags : Set where
  constructor permission-flags
  field
    allowed : Bool
    denied  : Bool

empty-flags : PermissionFlags
empty-flags = permission-flags false false

record PermissionMask : Set where
  constructor permission-mask
  field
    allowed : Bool
    denied  : Bool

permission-mask-all : PermissionMask
permission-mask-all = permission-mask true true

apply-bit : Bool → Bool → Bool → Bool
apply-bit mask value old = if mask then value else old

apply-mask :
  PermissionMask → PermissionFlags → PermissionFlags → PermissionFlags
apply-mask mask values old =
  permission-flags
    (apply-bit
      (PermissionMask.allowed mask)
      (PermissionFlags.allowed values)
      (PermissionFlags.allowed old))
    (apply-bit
      (PermissionMask.denied mask)
      (PermissionFlags.denied values)
      (PermissionFlags.denied old))

masked-new : PermissionMask → PermissionFlags → PermissionFlags
masked-new mask values =
  permission-flags
    (PermissionMask.allowed mask && PermissionFlags.allowed values)
    (PermissionMask.denied mask && PermissionFlags.denied values)

record PackageEntry : Set where
  constructor package-entry
  field
    uid      : Nat
    flags    : PermissionFlags
    packages : List String

is-allowed : PackageEntry → Bool
is-allowed entry = PermissionFlags.allowed (PackageEntry.flags entry)

is-denied : PackageEntry → Bool
is-denied entry = PermissionFlags.denied (PackageEntry.flags entry)

find : Nat → List PackageEntry → Maybe PackageEntry
find uid [] = nothing
find uid (entry ∷ rest) with nat-eq uid (PackageEntry.uid entry)
... | true = just entry
... | false = find uid rest

update-entry :
  Nat →
  List String →
  PermissionMask →
  PermissionFlags →
  PackageEntry →
  PackageEntry
update-entry uid packages mask values entry =
  package-entry
    uid
    (apply-mask mask values (PackageEntry.flags entry))
    (append-unique-strings (PackageEntry.packages entry) packages)

update :
  Nat →
  List String →
  PermissionMask →
  PermissionFlags →
  List PackageEntry →
  List PackageEntry
update uid packages mask values [] =
  package-entry uid (masked-new mask values) packages ∷ []
update uid packages mask values (entry ∷ rest)
  with nat-eq uid (PackageEntry.uid entry)
... | true = update-entry uid packages mask values entry ∷ rest
... | false = entry ∷ update uid packages mask values rest

remove : Nat → List PackageEntry → List PackageEntry
remove uid [] = []
remove uid (entry ∷ rest) with nat-eq uid (PackageEntry.uid entry)
... | true = rest
... | false = entry ∷ remove uid rest
