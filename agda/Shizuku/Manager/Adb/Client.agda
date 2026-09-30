{-# OPTIONS --safe #-}

module Shizuku.Manager.Adb.Client where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Nat using (Nat)

open import Shizuku.Port.Prelude
open import Shizuku.Manager.Adb.Protocol

data Transport : Set where
  plain : Transport
  tls   : Transport

data HandshakeState : Set where
  disconnected : HandshakeState
  awaiting-server : Transport → HandshakeState
  awaiting-after-signature : HandshakeState
  awaiting-after-public-key : HandshakeState
  ready : Transport → HandshakeState
  failed : HandshakeState

data HandshakeEffect : Set where
  open-socket : HandshakeEffect
  send : Command → Nat → Nat → HandshakeEffect
  send-auth-signature : HandshakeEffect
  send-auth-public-key : HandshakeEffect
  start-tls-handshake : HandshakeEffect
  handshake-error : HandshakeEffect

record HandshakeTransition : Set where
  constructor handshake-transition
  field
    state   : HandshakeState
    effects : List HandshakeEffect

connect-plan : HandshakeTransition
connect-plan =
  handshake-transition
    (awaiting-server plain)
    (open-socket ∷ send connection adb-version max-data ∷ [])

receive-initial :
  Nat → Command → Nat → HandshakeTransition
receive-initial sdk start-tls arg0 with start-tls
... | connection =
  handshake-transition (ready plain) []
... | Shizuku.Manager.Adb.Protocol.start-tls with 29 ≤ᵇ sdk
...   | false = handshake-transition failed (handshake-error ∷ [])
...   | true =
      handshake-transition
        (awaiting-server tls)
        (send Shizuku.Manager.Adb.Protocol.start-tls stls-version 0 ∷
         start-tls-handshake ∷ [])
... | auth with nat-eq arg0 auth-token
...   | false = handshake-transition failed (handshake-error ∷ [])
...   | true =
      handshake-transition
        awaiting-after-signature
        (send-auth-signature ∷ [])
... | _ = handshake-transition failed (handshake-error ∷ [])

after-signature : Command → HandshakeTransition
after-signature connection =
  handshake-transition (ready plain) []
after-signature _ =
  handshake-transition
    awaiting-after-public-key
    (send-auth-public-key ∷ [])

after-public-key : Command → HandshakeTransition
after-public-key connection =
  handshake-transition (ready plain) []
after-public-key _ =
  handshake-transition failed (handshake-error ∷ [])

data ShellState : Set where
  opening : ShellState
  streaming : Nat → ShellState
  closed : ShellState
  shell-error : ShellState

data ShellEffect : Set where
  open-shell : ShellEffect
  deliver-output : ShellEffect
  acknowledge-write : Nat → ShellEffect
  acknowledge-close : Nat → ShellEffect
  shell-protocol-error : ShellEffect

record ShellTransition : Set where
  constructor shell-transition
  field
    state   : ShellState
    effects : List ShellEffect

shell-open-reply : Command → Nat → ShellTransition
shell-open-reply okay remote-id =
  shell-transition (streaming remote-id) []
shell-open-reply close-stream remote-id =
  shell-transition closed (acknowledge-close remote-id ∷ [])
shell-open-reply _ _ =
  shell-transition shell-error (shell-protocol-error ∷ [])

shell-message : Nat → Command → Nat → ShellTransition
shell-message local-id write remote-id =
  shell-transition
    (streaming remote-id)
    (deliver-output ∷ acknowledge-write remote-id ∷ [])
shell-message local-id close-stream remote-id =
  shell-transition closed (acknowledge-close remote-id ∷ [])
shell-message _ _ _ =
  shell-transition shell-error (shell-protocol-error ∷ [])
