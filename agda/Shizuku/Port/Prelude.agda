{-# OPTIONS --safe #-}

module Shizuku.Port.Prelude where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat; zero; suc)
open import Agda.Builtin.String using (String; primStringEquality)

if_then_else_ : {A : Set} → Bool → A → A → A
if true then x else y = x
if false then x else y = y

not : Bool → Bool
not true = false
not false = true

_&&_ : Bool → Bool → Bool
true && b = b
false && _ = false

_||_ : Bool → Bool → Bool
true || _ = true
false || b = b

nat-eq : Nat → Nat → Bool
nat-eq zero zero = true
nat-eq zero (suc _) = false
nat-eq (suc _) zero = false
nat-eq (suc a) (suc b) = nat-eq a b

_≤ᵇ_ : Nat → Nat → Bool
zero ≤ᵇ _ = true
suc _ ≤ᵇ zero = false
suc a ≤ᵇ suc b = a ≤ᵇ b

_<ᵇ_ : Nat → Nat → Bool
a <ᵇ b = suc a ≤ᵇ b

string-eq : String → String → Bool
string-eq = primStringEquality

member-nat : Nat → List Nat → Bool
member-nat x [] = false
member-nat x (y ∷ ys) with nat-eq x y
... | true = true
... | false = member-nat x ys

member-string : String → List String → Bool
member-string x [] = false
member-string x (y ∷ ys) with string-eq x y
... | true = true
... | false = member-string x ys

remove-nat : Nat → List Nat → List Nat
remove-nat x [] = []
remove-nat x (y ∷ ys) with nat-eq x y
... | true = remove-nat x ys
... | false = y ∷ remove-nat x ys

append-unique-string : List String → String → List String
append-unique-string xs x with member-string x xs
... | true = xs
... | false = append xs (x ∷ [])
  where
  append : List String → List String → List String
  append [] ys = ys
  append (z ∷ zs) ys = z ∷ append zs ys

append-unique-strings : List String → List String → List String
append-unique-strings xs [] = xs
append-unique-strings xs (y ∷ ys) =
  append-unique-strings (append-unique-string xs y) ys

data Result (A E : Set) : Set where
  ok : A → Result A E
  error : E → Result A E

record Pair (A B : Set) : Set where
  constructor _,_
  field
    first : A
    second : B
