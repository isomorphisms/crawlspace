{-# OPTIONS --safe #-}

module Shizuku.Manager.Adb.Pairing where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

open import Shizuku.Port.Prelude

Byte : Set
Byte = Nat

Bytes : Set
Bytes = List Byte

current-header-version : Nat
current-header-version = 1

min-header-version : Nat
min-header-version = 1

max-header-version : Nat
max-header-version = 1

max-peer-info-size : Nat
max-peer-info-size = 8192

max-payload-size : Nat
max-payload-size = 16384

exported-key-size : Nat
exported-key-size = 64

pairing-header-size : Nat
pairing-header-size = 6

exported-key-label : String
exported-key-label = "adb-label"

data PacketType : Set where
  spake2-message : PacketType
  peer-info      : PacketType

packet-type-code : PacketType → Nat
packet-type-code spake2-message = 0
packet-type-code peer-info = 1

record Header : Set where
  constructor header
  field
    version : Nat
    type    : PacketType
    payload : Nat

valid-header : Header → Bool
valid-header h =
  (min-header-version ≤ᵇ Header.version h)
  &&
  (Header.version h ≤ᵇ max-header-version)
  &&
  (0 <ᵇ Header.payload h)
  &&
  (Header.payload h ≤ᵇ max-payload-size)

data State : Set where
  ready               : State
  exchanging-messages : State
  exchanging-peer-info : State
  stopped             : State

data PairingFailure : Set where
  tls-failure             : PairingFailure
  context-creation-failed : PairingFailure
  bad-message-header      : PairingFailure
  wrong-message-type      : PairingFailure
  cipher-init-failed      : PairingFailure
  encryption-failed       : PairingFailure
  invalid-pairing-code    : PairingFailure
  wrong-peer-info-size    : PairingFailure

data Effect : Set where
  open-tls13-connection : Effect
  export-tls-key-material : String → Nat → Effect
  create-spake2-context : Effect
  send-spake2-message   : Effect
  initialize-cipher     : Effect
  encrypt-peer-info     : Effect
  send-peer-info        : Effect
  decrypt-peer-info     : Effect
  destroy-pairing-context : Effect

record Transition : Set where
  constructor transition
  field
    state   : State
    failure : Maybe PairingFailure
    effects : List Effect

start-effects : List Effect
start-effects =
  open-tls13-connection Agda.Builtin.List.∷
  export-tls-key-material exported-key-label exported-key-size Agda.Builtin.List.∷
  create-spake2-context Agda.Builtin.List.∷
  send-spake2-message Agda.Builtin.List.∷
  Agda.Builtin.List.[]

begin : Transition
begin = transition exchanging-messages nothing start-effects

spake2-reply : Header → Bool → Transition
spake2-reply h cipher-initialized with valid-header h
... | false = transition stopped (just bad-message-header) Agda.Builtin.List.[]
... | true with Header.type h
...   | peer-info =
      transition stopped (just wrong-message-type) Agda.Builtin.List.[]
...   | spake2-message with cipher-initialized
...     | false =
        transition stopped (just cipher-init-failed) Agda.Builtin.List.[]
...     | true =
        transition exchanging-peer-info nothing
          (encrypt-peer-info Agda.Builtin.List.∷
           send-peer-info Agda.Builtin.List.∷
           decrypt-peer-info Agda.Builtin.List.∷
           Agda.Builtin.List.[])

peer-info-reply :
  Header → Bool → Nat → Transition
peer-info-reply h decrypts decrypted-size with valid-header h
... | false = transition stopped (just bad-message-header) Agda.Builtin.List.[]
... | true with Header.type h
...   | spake2-message =
      transition stopped (just wrong-message-type) Agda.Builtin.List.[]
...   | peer-info with decrypts
...     | false =
        transition stopped (just invalid-pairing-code) Agda.Builtin.List.[]
...     | true with nat-eq decrypted-size max-peer-info-size
...       | false =
          transition stopped (just wrong-peer-info-size) Agda.Builtin.List.[]
...       | true =
          transition stopped nothing
            (destroy-pairing-context Agda.Builtin.List.∷ Agda.Builtin.List.[])
