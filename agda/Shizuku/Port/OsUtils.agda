{-# OPTIONS --safe #-}

module Shizuku.Port.OsUtils where

open import Agda.Builtin.Maybe using (Maybe)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

record OsSnapshot : Set where
  constructor os-snapshot
  field
    uid             : Nat
    pid             : Nat
    selinux-context : Maybe String

get-uid : OsSnapshot → Nat
get-uid = OsSnapshot.uid

get-pid : OsSnapshot → Nat
get-pid = OsSnapshot.pid

get-selinux-context : OsSnapshot → Maybe String
get-selinux-context = OsSnapshot.selinux-context
