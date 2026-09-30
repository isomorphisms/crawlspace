{-# OPTIONS --safe #-}

module Shizuku.Manager where

import Shizuku.Manager.Settings
import Shizuku.Manager.Authorization
import Shizuku.Manager.ServiceStatus
import Shizuku.Manager.Starter
import Shizuku.Manager.Adb.Protocol
import Shizuku.Manager.Adb.Message
import Shizuku.Manager.Adb.Client
import Shizuku.Manager.Boot
import Shizuku.Manager.Shell
import Shizuku.Manager.Provider
import Shizuku.Manager.Adb.Key
import Shizuku.Manager.Adb.Mdns
import Shizuku.Manager.Adb.Pairing
import Shizuku.Manager.Adb.PairingService
import Shizuku.Manager.Receiver
import Shizuku.Manager.PermissionRequest
import Shizuku.Manager.Apps
import Shizuku.Manager.Home
import Shizuku.Manager.SystemApis
import Shizuku.Manager.ShellBinderRequest
import Shizuku.Manager.Environment
