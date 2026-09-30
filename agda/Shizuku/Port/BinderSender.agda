{-# OPTIONS --safe #-}

module Shizuku.Port.BinderSender where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

open import Shizuku.Port.Prelude

record PackageCandidate : Set where
  constructor package-candidate
  field
    package-name              : String
    requests-manager          : Bool
    manager-permission-granted : Bool
    requests-api              : Bool

data BinderTarget : Set where
  no-target : BinderTarget
  manager-target : BinderTarget
  user-app-target : String → BinderTarget

select-target : List PackageCandidate → BinderTarget
select-target [] = no-target
select-target (package ∷ rest)
  with PackageCandidate.requests-manager package
     | PackageCandidate.manager-permission-granted package
     | PackageCandidate.requests-api package
... | true | true | _ = manager-target
... | true | false | _ = select-target rest
... | false | _ | true =
  user-app-target (PackageCandidate.package-name package)
... | false | _ | false = select-target rest

record ObserverState : Set where
  constructor observer-state
  field
    pids : List Nat
    uids : List Nat

empty-observers : ObserverState
empty-observers = observer-state [] []

data ObserverEffect : Set where
  inspect-and-send : Nat → Nat → ObserverEffect

record ObserverTransition : Set where
  constructor observer-transition
  field
    state   : ObserverState
    effects : List ObserverEffect

process-starts : Nat → Nat → ObserverState → ObserverTransition
process-starts pid uid state with member-nat pid (ObserverState.pids state)
... | true = observer-transition state []
... | false =
  observer-transition
    (observer-state (pid ∷ ObserverState.pids state) (ObserverState.uids state))
    (inspect-and-send uid pid ∷ [])

foreground-changed :
  Nat → Nat → Bool → ObserverState → ObserverTransition
foreground-changed pid uid foreground state with foreground
... | false = observer-transition state []
... | true = process-starts pid uid state

process-died : Nat → ObserverState → ObserverState
process-died pid state =
  observer-state
    (remove-nat pid (ObserverState.pids state))
    (ObserverState.uids state)

uid-starts : Nat → ObserverState → ObserverTransition
uid-starts uid state with member-nat uid (ObserverState.uids state)
... | true = observer-transition state []
... | false =
  observer-transition
    (observer-state (ObserverState.pids state) (uid ∷ ObserverState.uids state))
    (inspect-and-send uid 0 ∷ [])

uid-cached-changed :
  Nat → Bool → ObserverState → ObserverTransition
uid-cached-changed uid cached state with cached
... | true = observer-transition state []
... | false = uid-starts uid state

uid-gone : Nat → ObserverState → ObserverState
uid-gone uid state =
  observer-state
    (ObserverState.pids state)
    (remove-nat uid (ObserverState.uids state))
