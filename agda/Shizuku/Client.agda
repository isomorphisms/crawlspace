{-# OPTIONS --safe #-}

module Shizuku.Client where

open import Agda.Builtin.Maybe using (Maybe; nothing; just)

open import Shizuku.Types
open import Shizuku.Provider using (BinderHandle)

record BoundInfo : Set where
  constructor bound-info
  field
    binder          : BinderHandle
    server-uid      : Uid
    server-version  : ApiVersion
    selinux-context : SELinuxContext
    permission      : Grant

data ClientState : Set where
  disconnected : ClientState
  bound        : BoundInfo → ClientState

binder-received :
  BinderHandle →
  Uid →
  ApiVersion →
  SELinuxContext →
  Grant →
  ClientState
binder-received binder uid version context grant =
  bound (bound-info binder uid version context grant)

binder-died : ClientState → ClientState
binder-died disconnected = disconnected
binder-died (bound _)     = disconnected

current-permission : ClientState → Maybe Grant
current-permission disconnected = nothing
current-permission (bound info)  = just (BoundInfo.permission info)
