{-# OPTIONS --safe #-}

module Shizuku.Port.HandlerUtil where

open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat)

Handler : Set
Handler = Nat

record State : Set where
  constructor state
  field
    main-handler : Maybe Handler

initial : State
initial = state nothing

set-main-handler : Handler → State
set-main-handler handler = state (just handler)

get-main-handler : State → Maybe Handler
get-main-handler = State.main-handler
