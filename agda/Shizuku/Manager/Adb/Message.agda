{-# OPTIONS --safe #-}

module Shizuku.Manager.Adb.Message where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat; zero; suc)

open import Shizuku.Port.Prelude
open import Shizuku.Manager.Adb.Protocol

Byte : Set
Byte = Nat

length : List Byte → Nat
length [] = 0
length (_ ∷ rest) = suc (length rest)

_+_ : Nat → Nat → Nat
zero + b = b
suc a + b = suc (a + b)

checksum : List Byte → Nat
checksum [] = 0
checksum (x ∷ rest) = x + checksum rest

record WireMessage : Set where
  constructor wire-message
  field
    command-code-field : Nat
    arg0               : Nat
    arg1               : Nat
    data-length        : Nat
    data-checksum      : Nat
    magic              : Nat
    payload-bytes      : List Byte

decode-command : Nat → Maybe Command
decode-command n with nat-eq n (command-code sync)
... | true = just sync
... | false with nat-eq n (command-code connection)
...   | true = just connection
...   | false with nat-eq n (command-code auth)
...     | true = just auth
...     | false with nat-eq n (command-code open-stream)
...       | true = just open-stream
...       | false with nat-eq n (command-code okay)
...         | true = just okay
...         | false with nat-eq n (command-code close-stream)
...           | true = just close-stream
...           | false with nat-eq n (command-code write)
...             | true = just write
...             | false with nat-eq n (command-code start-tls)
...               | true = just start-tls
...               | false = nothing

validate : WireMessage → Bool
validate message with decode-command (WireMessage.command-code-field message)
... | nothing = false
... | just command =
  nat-eq (WireMessage.magic message) (command-magic command)
  &&
  nat-eq (WireMessage.data-length message) (length (WireMessage.payload-bytes message))
  &&
  nat-eq (WireMessage.data-checksum message) (checksum (WireMessage.payload-bytes message))

header-length : Nat
header-length = 24
