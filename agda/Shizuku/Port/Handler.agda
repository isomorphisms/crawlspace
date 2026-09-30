{-# OPTIONS --safe #-}

module Shizuku.Port.Handler where

data HandlerKind : Set where
  main-handler   : HandlerKind
  worker-handler : HandlerKind

data WorkerThread : Set where
  worker-thread : WorkerThread

main : HandlerKind
main = main-handler

worker : HandlerKind
worker = worker-handler
