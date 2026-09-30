{-# OPTIONS --safe #-}

module Shizuku.Manager.Adb.Protocol where

open import Agda.Builtin.Nat using (Nat)

data Command : Set where
  sync : Command
  connection : Command
  auth : Command
  open-stream : Command
  okay : Command
  close-stream : Command
  write : Command
  start-tls : Command

command-code : Command → Nat
command-code sync = 1129208147
command-code connection = 1314410051
command-code auth = 1213486401
command-code open-stream = 1313165391
command-code okay = 1497451343
command-code close-stream = 1163086915
command-code write = 1163154007
command-code start-tls = 1397511251

command-magic : Command → Nat
command-magic sync = 3165759148
command-magic connection = 2980557244
command-magic auth = 3081480894
command-magic open-stream = 2981801904
command-magic okay = 2797515952
command-magic close-stream = 3131880380
command-magic write = 3131813288
command-magic start-tls = 2897456044

adb-version : Nat
adb-version = 16777216

max-data : Nat
max-data = 4096

stls-version : Nat
stls-version = 16777216

auth-token : Nat
auth-token = 1

auth-signature : Nat
auth-signature = 2

auth-rsa-public-key : Nat
auth-rsa-public-key = 3
