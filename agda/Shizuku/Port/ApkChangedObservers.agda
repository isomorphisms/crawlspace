{-# OPTIONS --safe #-}

module Shizuku.Port.ApkChangedObservers where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String; primStringEquality)

open import Shizuku.Port.Prelude

Listener : Set
Listener = Nat

record Observer : Set where
  constructor observer
  field
    parent-path : String
    listeners   : List Listener
    watching    : Bool

same-path : String → Observer → Bool
same-path path obs = primStringEquality path (Observer.parent-path obs)

add-listener : Listener → List Listener → List Listener
add-listener listener listeners with member-nat listener listeners
... | true = listeners
... | false = listener ∷ listeners

start :
  String → Listener → List Observer → List Observer
start parent listener [] =
  observer parent (listener ∷ []) true ∷ []
start parent listener (obs ∷ rest) with same-path parent obs
... | true =
  observer
    (Observer.parent-path obs)
    (add-listener listener (Observer.listeners obs))
    true
  ∷ rest
... | false = obs ∷ start parent listener rest

remove-listener : Listener → List Listener → List Listener
remove-listener = remove-nat

stop : Listener → List Observer → List Observer
stop listener [] = []
stop listener (obs ∷ rest)
  with remove-listener listener (Observer.listeners obs)
... | [] = stop listener rest
... | remaining =
  observer
    (Observer.parent-path obs)
    remaining
    (Observer.watching obs)
  ∷ stop listener rest

data FileEvent : Set where
  base-apk-deleted : FileEvent
  ignored-event    : FileEvent
  other-event      : FileEvent

record EventResult : Set where
  constructor event-result
  field
    observer-after : Observer
    notify         : List Listener

on-event : FileEvent → Observer → EventResult
on-event base-apk-deleted obs =
  event-result
    (observer
      (Observer.parent-path obs)
      (Observer.listeners obs)
      false)
    (Observer.listeners obs)
on-event ignored-event obs = event-result obs []
on-event other-event obs = event-result obs []
