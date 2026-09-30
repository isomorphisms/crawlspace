{-# OPTIONS --safe #-}

module Shizuku.Port.ServiceConnections where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String; primStringEquality)

open import Shizuku.Port.Prelude using (nat-eq)

ConnectionHandle : Set
ConnectionHandle = Nat

record CacheEntry : Set where
  constructor cache-entry
  field
    key        : String
    connection : ConnectionHandle

find : String → List CacheEntry → Maybe ConnectionHandle
find key [] = nothing
find key (entry ∷ rest)
  with primStringEquality key (CacheEntry.key entry)
... | true = just (CacheEntry.connection entry)
... | false = find key rest

get-or-insert :
  String → ConnectionHandle → List CacheEntry → List CacheEntry
get-or-insert key fresh entries with find key entries
... | just _ = entries
... | nothing = cache-entry key fresh ∷ entries

remove-connection :
  ConnectionHandle → List CacheEntry → List CacheEntry
remove-connection connection [] = []
remove-connection connection (entry ∷ rest)
  with nat-eq connection (CacheEntry.connection entry)
... | true = remove-connection connection rest
... | false = entry ∷ remove-connection connection rest