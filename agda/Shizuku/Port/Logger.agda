{-# OPTIONS --safe #-}

module Shizuku.Port.Logger where

open import Agda.Builtin.String using (String)

data Level : Set where
  verbose : Level
  debug   : Level
  info    : Level
  warn    : Level
  error   : Level

record LogEntry : Set where
  constructor log-entry
  field
    tag     : String
    level   : Level
    message : String
