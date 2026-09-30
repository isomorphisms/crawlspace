{-# OPTIONS --safe #-}

module Shizuku.Manager.Starter where

open import Agda.Builtin.String using (String; primStringAppend)

record Paths : Set where
  constructor paths
  field
    native-library-dir : String
    apk-source-dir     : String

record Commands : Set where
  constructor commands
  field
    user-command     : String
    adb-command      : String
    internal-command : String

make-commands : String → String → Commands
make-commands starter-file apk-source =
  commands
    starter-file
    (primStringAppend "adb shell " starter-file)
    (primStringAppend
      (primStringAppend starter-file " --apk=")
      apk-source)
