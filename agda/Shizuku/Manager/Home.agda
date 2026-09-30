{-# OPTIONS --safe #-}

module Shizuku.Manager.Home where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

record RemoteFacts : Set where
  constructor remote-facts
  field
    binder-alive             : Bool
    uid                      : Nat
    api-version              : Nat
    patch-version            : Nat
    selinux-context          : Maybe String
    grant-runtime-permission : Bool
    compatibility-check-ok   : Bool

data HomeStatus : Set where
  stopped : HomeStatus
  running :
    Nat → Nat → Nat → Maybe String → Bool → HomeStatus
  failed : HomeStatus

load-status : RemoteFacts → HomeStatus
load-status facts with RemoteFacts.binder-alive facts
... | false = stopped
... | true with RemoteFacts.compatibility-check-ok facts
...   | false = failed
...   | true =
      running
        (RemoteFacts.uid facts)
        (RemoteFacts.api-version facts)
        (RemoteFacts.patch-version facts)
        (RemoteFacts.selinux-context facts)
        (RemoteFacts.grant-runtime-permission facts)
