# Moon follow-ups for capability discovery

The protocol decision and focused implementation are complete in commit
`1b41c63d67aabbbbc33904cf5d611776cf4cc235` on branch
`capability-discovery-v1`. The jobs below may propagate that result. They must
return any semantic conflict or needed redesign instead of choosing a new
protocol.

## Moon job 1: hosted build and artifact receipt

Work in `isomorphisms/crawlspace`,
<https://github.com/isomorphisms/crawlspace>, from the current
`capability-discovery-v1` branch.

The settled prerequisite is commit
`1b41c63d67aabbbbc33904cf5d611776cf4cc235`, “Add bounded capability discovery
protocol.” First verify that the branch still contains that commit and that
`src/crawlspace.c`, `tests/protocol_test.c`, `docs/protocol.md`, and the host
test job still express the same protocol. If the implementation changed after
that commit, bind all evidence to the current exact head and stop if the change
alters protocol semantics.

Perform only mechanical build, test, and receipt work:

1. Run `make test` on the hosted x86-64 runner.
2. Run the same test with AddressSanitizer and UndefinedBehaviorSanitizer. If
   LeakSanitizer cannot inspect runner processes, record that exact limitation;
   do not call it a leak pass.
3. Build the existing Android targets through
   `scripts/build_android.sh all` with the workflow's pinned NDK. Do not add an
   ABI or change the API floor.
4. Verify the two outputs are ELF executables for `armeabi-v7a` and
   `arm64-v8a`, record their byte sizes and SHA-256 digests, and preserve the
   workflow artifact URL.
5. Add or update one receipt under `docs/receipts/` with the source head, NDK
   version, exact commands, typed pass/fail results, artifact identities, and
   direct workflow URL.

Do not change discovery fields, status numbers, capability names,
authentication scope, timeout behavior, `CSP1`, bootstrap, Binder access, or
root behavior. A simple compiler portability defect may receive a narrow fix
only when it preserves the documented bytes and host outcomes exactly. Stop
and return any broader failure for Earth or Sun.

Do not merge, release, or claim MIRO A1 behavior. Return the exact head and
hosted receipt.

## Moon job 2: MIRO A1 behavior receipt

Work in `isomorphisms/crawlspace`,
<https://github.com/isomorphisms/crawlspace>, after Moon job 1 has produced a
passing `armeabi-v7a` artifact and exact digest from a head containing
`1b41c63d67aabbbbc33904cf5d611776cf4cc235`.

This is a mechanical physical acceptance and receipt job for the MIRO A1:
Android 14, SDK 34, `armeabi-v7a`, shell UID 2000. Do not compile or install a
compiler/build tool on the phone. Deliver the exact prebuilt artifact through
the established Cat Food route and verify its digest before execution.

Use the existing self-ADB bootstrap and token locations. Never print, copy into
the receipt, or commit the bearer token. Record these observations separately:

1. First `crawlspace discover` returns `status=ready`, transport version 2,
   discovery version 1, `daemon_uid=2000`, and exactly the two documented
   capabilities.
2. Discovery with the returned identity reports `ready` and the same identity.
3. Restart the daemon through the existing ADB shell bootstrap, then discover
   with the old identity. It must report `restarted` and a different identity.
4. A temporary wrong token receives `status=denied` and exit 77. Do not replace
   or expose the real token while making this check.
5. Stop the daemon and verify `status=unavailable`,
   `reason=daemon-absent`, exit 69; then restore the daemon.
6. Verify `crawlspace run /system/bin/id` still reports `uid=2000(shell)` after
   restoration.

Do not test a Binder operation, root bootstrap, unrelated executable, or a
different Android device. Do not interpret hosted evidence as a phone pass.
Add one receipt under `docs/receipts/` containing the source head, artifact
digest, device identity, exact observed nonsecret output, and each PASS/FAIL.
Return any SELinux, ADB, token, transport, or identity divergence without
changing the protocol.

Do not merge, release, rotate the user's lasting token, or leave the daemon
stopped.
