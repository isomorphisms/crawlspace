{-# OPTIONS --safe #-}

module Shizuku.Port.BinderContainer where

open import Agda.Builtin.Nat using (Nat)

BinderHandle : Set
BinderHandle = Nat

record BinderContainer : Set where
  constructor binder-container
  field
    binder : BinderHandle

describe-contents : BinderContainer → Nat
describe-contents _ = 0

write-strong-binder : BinderContainer → BinderHandle
write-strong-binder = BinderContainer.binder

read-strong-binder : BinderHandle → BinderContainer
read-strong-binder = binder-container
