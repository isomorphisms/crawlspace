{-# OPTIONS --safe #-}

module Shizuku.Manager.Apps where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

record App : Set where
  constructor app-info
  field
    package-name : String
    uid          : Nat
    granted      : Bool

granted-count : List App → Nat
granted-count [] = 0
granted-count (app ∷ rest) with App.granted app
... | true = Agda.Builtin.Nat.suc (granted-count rest)
... | false = granted-count rest

record LoadResult : Set where
  constructor load-result
  field
    packages : List App
    count    : Nat

load : List App → LoadResult
load apps = load-result apps (granted-count apps)
