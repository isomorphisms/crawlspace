{-# OPTIONS --safe #-}

module Shizuku.Port.AbiUtil where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.String using (String)

has-32-bit : List String → Bool
has-32-bit [] = false
has-32-bit (_ ∷ _) = true
