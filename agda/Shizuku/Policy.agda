{-# OPTIONS --safe #-}

module Shizuku.Policy where

open import Agda.Builtin.Bool using (Bool; true; false)

open import Shizuku.Protocol

data CallerClass : Set where
  server-self       : CallerClass
  manager           : CallerClass
  attached-allowed  : CallerClass
  attached-denied   : CallerClass
  manifest-granted  : CallerClass
  unattached        : CallerClass

data Requirement : Set where
  ownership-check   : Requirement
  attached-client   : Requirement
  privileged        : Requirement
  manager-only      : Requirement
  sui-placeholder   : Requirement

requirement : Call → Requirement
requirement get-version                           = privileged
requirement get-uid                               = privileged
requirement (check-permission _)                  = privileged
requirement (new-process _)                       = privileged
requirement get-selinux-context                   = privileged
requirement (get-system-property _ _)             = privileged
requirement (set-system-property _ _)             = privileged
requirement (add-user-service _)                  = privileged
requirement (remove-user-service _)               = privileged
requirement (request-permission _)                = attached-client
requirement check-self-permission                 = attached-client
requirement should-show-permission-rationale      = attached-client
requirement (attach-application _)                = ownership-check
requirement exit                                  = manager-only
requirement (attach-user-service _)               = manager-only
requirement (dispatch-package-changed _)          = sui-placeholder
requirement (is-hidden _)                         = sui-placeholder
requirement (dispatch-permission-result _)        = manager-only
requirement (get-flags-for-uid _ _)               = manager-only
requirement (update-flags-for-uid _ _ _)          = manager-only

authorized : CallerClass → Requirement → Bool
authorized server-self _              = true
authorized manager _                  = true
authorized attached-allowed privileged = true
authorized manifest-granted privileged = true
authorized attached-allowed attached-client = true
authorized attached-denied attached-client  = true
authorized attached-allowed ownership-check = true
authorized attached-denied ownership-check  = true
authorized manifest-granted ownership-check = true
authorized unattached ownership-check       = true
authorized _ sui-placeholder          = true
authorized _ _                        = false

may-call : CallerClass → Call → Bool
may-call caller call = authorized caller (requirement call)
