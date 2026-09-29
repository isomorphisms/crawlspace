# Native transport protocol

All integers are unsigned 32-bit values in network byte order. All counted
byte strings are a length followed by exactly that many bytes. The daemon
accepts one request per loopback TCP connection.

## `CSP1`: command execution

`CSP1` remains the original command request:

1. four bytes `CSP1`;
2. counted bearer token;
3. argument count;
4. one counted byte string per argument.

The response remains its original stream of counted output chunks, a zero
length, and the remote exit status. Capability discovery does not change this
layout and cannot be requested through it.

## `CSP2`: capability discovery

The first discovery request has this exact layout:

1. four bytes `CSP2`;
2. counted bearer token, from 1 through 256 bytes on the wire;
3. operation number `1`, meaning `discover capabilities`;
4. expected daemon identity length, either `0` or `16`;
5. the expected 16 identity bytes when the length is `16`.

No command, path, Binder method, or open-ended capability name appears in this
request. An authenticated operation number outside the compiled operation
allowlist receives `operation denied`.

The response begins with four bytes `CSR2` and one status number:

| Number | Meaning |
| ---: | --- |
| 0 | ready; no prior identity was supplied or it matches |
| 1 | restarted; the supplied identity differs |
| 2 | bearer token denied |
| 3 | malformed request |
| 4 | authenticated operation denied |

Denied and malformed responses stop after the status. A ready or restarted
response continues with:

1. discovery schema version, currently `1`;
2. daemon UID;
3. counted 16-byte daemon identity;
4. capability count;
5. each capability as a counted UTF-8 byte string.

Schema version 1 emits only this compiled allowlist:

- `crawlspace.discovery.v1`
- `crawlspace.run.absolute-path.v1`

The list describes operations understood by this daemon. It grants no new
authority. In particular, it makes no claim about Binder, root, SELinux
permission, a particular executable, or an Android service.

## Authentication and authorization

The daemon loads one token file at start and keeps the bytes in memory. Leading
and interior whitespace remain part of the token; one trailing run of CR/LF is
removed. Empty files and files that fill the 256-byte read buffer are rejected.
The token is never printed or returned. Comparisons examine the complete
received and expected lengths without an early mismatch exit.

Possession of this token authorizes both current operations for the daemon
identity: bounded discovery and the existing absolute-path command request.
Discovery does not mint a token, narrow a token, or turn a reported capability
into a grant. Rotate the token file and restart the daemon to revoke the old
token.

The scope is deliberately named `local-bearer-token`. TCP loopback does not
expose Unix peer credentials. The protocol sends the bearer token to the
listening process without a protected channel, so a process that replaces the
listener can impersonate the endpoint and receive the token. The random daemon
identity only lets a caller compare this response with one it previously saw;
it is not cryptographic authentication. Binder, Unix peer credentials, and a
root bootstrap remain outside this protocol version.

## Timeouts and absence

The discovery client applies one timeout to connection establishment and socket
reads/writes. `CSP1` command connection establishment uses the same bound, but
its response stream has no I/O timeout, preserving commands that run silently
for longer. The daemon applies the timeout to each accepted socket, preventing
a partial request from holding the single request loop forever. The default is
5,000 ms.
`CRAWLSPACE_TIMEOUT_MS` may select 1 through 60,000 ms; other values are usage
errors.

The discovery CLI reports machine-readable availability outcomes:

| Outcome | Output | Exit status |
| --- | --- | ---: |
| no listener/refused route | `status=unavailable`, `reason=daemon-absent` | 69 |
| connect/read/write timeout | `status=unavailable`, `reason=timeout` | 124 |
| token or operation denial | `status=denied` | 77 |
| malformed protocol response | diagnostic on stderr | 65 |

`status=restarted` is a successful response with exit status 0. The caller must
discard assumptions tied to the old identity and use the capability list in the
new response. A caller that supplies no prior identity receives `status=ready`
because it requested no continuity comparison.
