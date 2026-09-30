{-# OPTIONS --safe #-}

module Shizuku.Port.ShizukuConfigManager where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

open import Shizuku.Port.Prelude
open import Shizuku.Port.ConfigManager

latest-version : Nat
latest-version = 2

write-delay-millis : Nat
write-delay-millis = 10000

config-path : String
config-path = "/data/user_de/0/com.android.shell/shizuku.json"

record InstalledUid : Set where
  constructor installed-uid
  field
    uid      : Nat
    packages : List String

overlaps : List String → List String → Bool
overlaps [] ys = false
overlaps (x ∷ xs) ys with member-string x ys
... | true = true
... | false = overlaps xs ys

installed-packages : Nat → List InstalledUid → List String
installed-packages uid [] = []
installed-packages uid (entry ∷ rest)
  with nat-eq uid (InstalledUid.uid entry)
... | true = InstalledUid.packages entry
... | false = installed-packages uid rest

deduplicate : List String → List String
deduplicate xs = go [] xs
  where
  go : List String → List String → List String
  go acc [] = acc
  go acc (x ∷ rest) = go (append-unique-string acc x) rest

clean-entry : List InstalledUid → PackageEntry → List PackageEntry
clean-entry installed entry with installed-packages (PackageEntry.uid entry) installed
... | [] = []
... | actual with overlaps (PackageEntry.packages entry) actual
...   | false = []
...   | true =
      package-entry
        (PackageEntry.uid entry)
        (PackageEntry.flags entry)
        (deduplicate (PackageEntry.packages entry)) ∷ []

clean-config : List InstalledUid → List PackageEntry → List PackageEntry
clean-config installed [] = []
clean-config installed (entry ∷ rest) =
  append (clean-entry installed entry) (clean-config installed rest)
  where
  append : List PackageEntry → List PackageEntry → List PackageEntry
  append [] ys = ys
  append (x ∷ xs) ys = x ∷ append xs ys

record RuntimePermissionSnapshot : Set where
  constructor runtime-permission
  field
    uid          : Nat
    package-name : String
    allowed      : Bool

import-runtime-permission :
  RuntimePermissionSnapshot → List PackageEntry → List PackageEntry
import-runtime-permission snapshot config =
  update
    (RuntimePermissionSnapshot.uid snapshot)
    (RuntimePermissionSnapshot.package-name snapshot ∷ [])
    permission-mask-all
    flags
    config
  where
  flags : PermissionFlags
  flags with RuntimePermissionSnapshot.allowed snapshot
  ... | true = permission-flags true false
  ... | false = permission-flags false false

import-runtime-permissions :
  List RuntimePermissionSnapshot → List PackageEntry → List PackageEntry
import-runtime-permissions [] config = config
import-runtime-permissions (snapshot ∷ rest) config =
  import-runtime-permissions rest
    (import-runtime-permission snapshot config)

initialize :
  List InstalledUid →
  List RuntimePermissionSnapshot →
  List PackageEntry →
  List PackageEntry
initialize installed runtime-permissions config =
  import-runtime-permissions runtime-permissions
    (clean-config installed config)
