{-# OPTIONS --safe #-}

module Shizuku.Port.ParcelFileDescriptorUtil where

open import Agda.Builtin.Nat using (Nat)

Descriptor : Set
Descriptor = Nat

data StreamDirection : Set where
  pipe-from-input  : StreamDirection
  pipe-to-output   : StreamDirection

record Pipe : Set where
  constructor pipe
  field
    read-side  : Descriptor
    write-side : Descriptor

transfer-buffer-bytes : Nat
transfer-buffer-bytes = 8192

record TransferPlan : Set where
  constructor transfer-plan
  field
    direction : StreamDirection
    transfer-pipe : Pipe
    daemon-thread : Descriptor

returned-side : StreamDirection → Pipe → Descriptor
returned-side pipe-from-input p = Pipe.read-side p
returned-side pipe-to-output p = Pipe.write-side p
