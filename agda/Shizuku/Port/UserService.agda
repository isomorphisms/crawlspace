{-# OPTIONS --safe #-}

module Shizuku.Port.UserService where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

BinderHandle : Set
BinderHandle = Nat

data ParsedArgument : Set where
  debug-name : String → ParsedArgument
  token      : String → ParsedArgument
  package    : String → ParsedArgument
  class-name : String → ParsedArgument
  uid        : Nat → ParsedArgument
  ignored    : String → ParsedArgument

record ParsedArgs : Set where
  constructor parsed-args
  field
    debug-name-value : Maybe String
    token-value      : Maybe String
    package-value    : Maybe String
    class-value      : Maybe String
    uid-value        : Maybe Nat

empty-args : ParsedArgs
empty-args = parsed-args nothing nothing nothing nothing nothing

apply-argument : ParsedArgument → ParsedArgs → ParsedArgs
apply-argument (debug-name name) args =
  parsed-args (just name)
    (ParsedArgs.token-value args)
    (ParsedArgs.package-value args)
    (ParsedArgs.class-value args)
    (ParsedArgs.uid-value args)
apply-argument (token value) args =
  parsed-args
    (ParsedArgs.debug-name-value args)
    (just value)
    (ParsedArgs.package-value args)
    (ParsedArgs.class-value args)
    (ParsedArgs.uid-value args)
apply-argument (package value) args =
  parsed-args
    (ParsedArgs.debug-name-value args)
    (ParsedArgs.token-value args)
    (just value)
    (ParsedArgs.class-value args)
    (ParsedArgs.uid-value args)
apply-argument (class-name value) args =
  parsed-args
    (ParsedArgs.debug-name-value args)
    (ParsedArgs.token-value args)
    (ParsedArgs.package-value args)
    (just value)
    (ParsedArgs.uid-value args)
apply-argument (uid value) args =
  parsed-args
    (ParsedArgs.debug-name-value args)
    (ParsedArgs.token-value args)
    (ParsedArgs.package-value args)
    (ParsedArgs.class-value args)
    (just value)
apply-argument (ignored _) args = args

parse-semantic-arguments : List ParsedArgument → ParsedArgs
parse-semantic-arguments = go empty-args
  where
  go : ParsedArgs → List ParsedArgument → ParsedArgs
  go args [] = args
  go args (arg ∷ rest) = go (apply-argument arg args) rest

data ConstructionPath : Set where
  constructor-with-context : ConstructionPath
  zero-argument-constructor : ConstructionPath

record CreatePlan : Set where
  constructor create-plan
  field
    package-name : String
    class-name   : String
    token        : String
    debug-name   : Maybe String
    uid          : Nat
    construction : ConstructionPath

data CreateError : Set where
  missing-package : CreateError
  missing-class   : CreateError
  missing-token   : CreateError
  missing-uid     : CreateError
  reflection-failed : CreateError

prepare-create : ParsedArgs → ConstructionPath → Maybe CreatePlan
prepare-create args construction with ParsedArgs.package-value args
... | nothing = nothing
... | just package-name with ParsedArgs.class-value args
...   | nothing = nothing
...   | just class-name with ParsedArgs.token-value args
...     | nothing = nothing
...     | just token-value with ParsedArgs.uid-value args
...       | nothing = nothing
...       | just uid-value =
          just
            (create-plan package-name class-name token-value
              (ParsedArgs.debug-name-value args)
              uid-value construction)
