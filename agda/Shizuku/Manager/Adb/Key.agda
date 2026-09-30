{-# OPTIONS --safe #-}

module Shizuku.Manager.Adb.Key where

open import Agda.Builtin.Bool using (Bool)
open import Agda.Builtin.List using (List)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String)

Byte : Set
Byte = Nat

Bytes : Set
Bytes = List Byte

android-keystore : String
android-keystore = "AndroidKeyStore"

encryption-key-alias : String
encryption-key-alias = "_adbkey_encryption_key_"

transformation : String
transformation = "AES/GCM/NoPadding"

iv-size-bytes : Nat
iv-size-bytes = 12

tag-size-bytes : Nat
tag-size-bytes = 16

rsa-bits : Nat
rsa-bits = 2048

android-pubkey-modulus-size : Nat
android-pubkey-modulus-size = 256

android-pubkey-modulus-words : Nat
android-pubkey-modulus-words = 64

rsa-public-key-struct-size : Nat
rsa-public-key-struct-size = 524

record StoredKey : Set where
  constructor stored-key
  field
    encrypted-private-key : Bytes

data PrivateKeyDecision : Set where
  use-stored-private-key : Bytes → PrivateKeyDecision
  generate-rsa-private-key : PrivateKeyDecision

choose-private-key : Maybe Bytes → Bool → PrivateKeyDecision
choose-private-key nothing decrypts = generate-rsa-private-key
choose-private-key (just bytes) true =
  use-stored-private-key bytes
choose-private-key (just bytes) false =
  generate-rsa-private-key

record AdbPublicKeyLayout : Set where
  constructor adb-public-key-layout
  field
    modulus-size-words : Nat
    n0inv              : Nat
    modulus-little-endian : Bytes
    rr-little-endian      : Bytes
    exponent               : Nat
    name                   : String

record CryptoEffects : Set₁ where
  field
    Key : Set
    Certificate : Set
    SSLContext : Set

    get-or-create-aes-gcm-key : Key
    decrypt-private-key : Key → Bytes → Maybe Bytes
    generate-rsa-2048 : Key
    encrypt-private-key : Key → Bytes → Maybe Bytes
    rsa-sign-adb-token : Key → Bytes → Bytes
    make-self-signed-certificate : Key → Certificate
    make-tls13-context : Key → Certificate → SSLContext
