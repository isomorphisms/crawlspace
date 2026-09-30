{-# OPTIONS --safe #-}

module Shizuku.Manager.Receiver where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.String using (String; primStringEquality)

request-binder-action : String
request-binder-action = "rikka.shizuku.intent.action.REQUEST_BINDER"

should-handle : String → Bool
should-handle action =
  primStringEquality action request-binder-action
