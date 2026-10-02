# Design

Crawl Space is an entrance below Android application privilege, not the final operating-system design.

## First boundary

The first implementation has two processes:

1. a normal client in Termux;
2. a small native daemon started by ADB as Android `shell` (`uid=2000`).

They communicate over loopback TCP. A random token kept in the Termux private directory authenticates requests. The daemon accepts only absolute executable paths and returns combined stdout/stderr plus the remote exit status.

The same transport also supports a bounded capability-discovery request. It is
a distinct protocol operation and CLI verb; it cannot carry a command. The
daemon answers from a compiled allowlist rather than deriving names from the
filesystem, PATH, Android services, or caller input.

The daemon deliberately refuses to start as an ordinary application uid. It accepts `shell` now and `root` later.

## Why keep this when Crawl Space grows

The command interface stays useful while the mechanism underneath it changes:

```text
today:     Termux -> crawlspace -> ADB-started shell process
later:     Termux -> crawlspace -> root process
later yet: programs -> crawlspace -> boot-integrated privileged service
```

Kernel/filesystem work such as TTL storage, append semantics, reclaim policy, or storage placement is separate. Crawl Space can install, inspect, test, and exercise those primitives without requiring every experiment to become an Android app.

## First acceptance

After self-ADB bootstrap:

```sh
crawlspace run /system/bin/id
```

must report `uid=2000(shell)`.

Then an already staged system-side tool can be reached through the same entrance:

```sh
crawlspace run /data/local/tmp/tmovvm voicemail list
```

That is the useful first milestone: ordinary Termux initiates an operation that actually executes under Android `shell`, without keeping an interactive ADB shell open.

## Known limitations of this first cut

- ADB is still required to start the daemon after reboot.
- The protocol is non-interactive.
- stdout and stderr are combined.
- A holder of the token can request any absolute executable path available to the daemon identity.
- The token is a local bearer secret. Loopback TCP supplies no peer UID and no
  cryptographic server identity. A successful discovery response proves only
  that the answering process knew the token supplied by the client.
- The per-start daemon identity detects replacement relative to an identity the
  caller already observed. It does not authenticate the binary or Android boot.
- This does not bypass SELinux; it exposes exactly what the daemon identity can do.

Those limitations are intentional. They make the shell boundary measurable before root or OS integration replaces the bootstrap.


## Longview control-plane slice

The listener must remain useful while ordinary work is in progress. Each
accepted request therefore runs in a short-lived handler process rather than in
the listener itself. The listener immediately returns to `accept`, so
capability/identity queries are not queued behind a long command.

The control-plane identity report deliberately separates:

- per-start continuity identity;
- listener PID;
- UID/authority;
- native-command-bridge role;
- compiled source build ID.

A PID is an observation, not an execution handle.

The listener socket is close-on-exec and connection handlers close their copy of
it. Executed commands also close the client control socket. This gives a useful
failure boundary: killing the listener removes the listening endpoint even when
an already accepted command is still alive.

This is only the first Longview slice. A later worker protocol still needs its
own operation identity, separate stdout/stderr, bounded retained output, explicit
caller-loss semantics, and independent result reopening. Those meanings belong
to IB; Crawl Space should provide the mechanism without inventing IB's task
model.


The physical acceptance harness keeps the destructive step opt-in. Its default
mode checks concurrent control without stopping the daemon. The
`--kill-listener` mode deliberately stops the listener and verifies that an
already accepted command can finish while the endpoint is gone. It does not
claim retained-result semantics; IB still owns the distinction between a live
command response and independently reopenable durable information.


The physical Longview acceptance now exercises the bounded-run primitive before
the listener-lifetime test: separate stdout/stderr, retained-prefix truncation,
and server-enforced timeout. These remain live synchronous transport semantics.
They do not turn the captured prefixes into IB durable results.
