{-# OPTIONS --safe #-}

module Shizuku.Port.ProviderCompat where

open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

open import Shizuku.Port.Prelude

data CallShape : Set where
  attribution-source-call : CallShape
  package-tag-call        : CallShape
  package-authority-call  : CallShape
  legacy-package-call     : CallShape

server-call-shape : Nat → CallShape
server-call-shape sdk with 31 ≤ᵇ sdk
... | true = attribution-source-call
... | false with 30 ≤ᵇ sdk
...   | true = package-tag-call
...   | false with 29 ≤ᵇ sdk
...     | true = package-authority-call
...     | false = legacy-package-call

starter-call-shape : Nat → CallShape
starter-call-shape = server-call-shape
