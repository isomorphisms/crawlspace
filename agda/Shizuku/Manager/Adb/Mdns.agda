{-# OPTIONS --safe #-}

module Shizuku.Manager.Adb.Mdns where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.Maybe using (Maybe; nothing; just)
open import Agda.Builtin.Nat using (Nat)
open import Agda.Builtin.String using (String; primStringEquality)

tls-connect-service : String
tls-connect-service = "_adb-tls-connect._tcp"

tls-pairing-service : String
tls-pairing-service = "_adb-tls-pairing._tcp"

record State : Set where
  constructor state
  field
    registered   : Bool
    running      : Bool
    service-name : Maybe String

initial : State
initial = state false false nothing

data Effect : Set where
  discover-services : String → Effect
  stop-discovery    : Effect
  resolve-service   : String → Effect
  report-port       : Nat → Effect

record Transition : Set where
  constructor transition
  field
    state  : State
    effect : Maybe Effect

start : String → State → Transition
start service-type old with State.running old
... | true = transition old nothing
... | false with State.registered old
...   | true =
      transition
        (state true true (State.service-name old))
        nothing
...   | false =
      transition
        (state false true (State.service-name old))
        (just (discover-services service-type))

stop : State → Transition
stop old with State.running old
... | false = transition old nothing
... | true with State.registered old
...   | false =
      transition
        (state false false (State.service-name old))
        nothing
...   | true =
      transition
        (state true false (State.service-name old))
        (just stop-discovery)

discovery-started : State → State
discovery-started old =
  state true (State.running old) (State.service-name old)

discovery-stopped : State → State
discovery-stopped old =
  state false (State.running old) (State.service-name old)

service-found : String → Effect
service-found name = resolve-service name

record ResolutionFacts : Set where
  constructor resolution-facts
  field
    name             : String
    port             : Nat
    host-is-local    : Bool
    port-in-use      : Bool

service-resolved : ResolutionFacts → State → Transition
service-resolved facts old
  with State.running old
     | ResolutionFacts.host-is-local facts
     | ResolutionFacts.port-in-use facts
... | true | true | true =
  transition
    (state
      (State.registered old)
      true
      (just (ResolutionFacts.name facts)))
    (just (report-port (ResolutionFacts.port facts)))
... | _ | _ | _ = transition old nothing

service-lost : String → State → Maybe Effect
service-lost name old with State.service-name old
... | nothing = nothing
... | just current with primStringEquality name current
...   | true = just (report-port 0)
...   | false = nothing
