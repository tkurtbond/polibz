# polibz design plan

A binding to zlib for poc, made for polout's PDF compression (polout's
PLAN.md, decisions 8 and 13), and usable by any poc program.

## Scope

- Deflate and inflate as streams, in the zlib, gzip and raw formats,
  and gzip-or-zlib detection when inflating (`AnyFormat`).
- Every deflate setting: level, window bits (9 to 15), memory level,
  strategy, and a preset dictionary.
- One-call `Compress` and `Uncompress`.
- Adler-32 and CRC-32.

Not bound: the gzip file functions (`gzopen` and the rest), which
open files themselves, so a program can't put a gzip stream inside
one of its own; a `Deflater` to a file `Sink` covers them. Also not
bound: `deflateParams`, `deflateTune`, `deflatePrime`,
`inflateBack`, `inflateSync`, `inflateMark`, gzip header access
(`deflateSetHeader`, `inflateGetHeader`), and checksum combining.
Each can be added when something needs it.

**zlib's standard API, not zlib-ng's own.** atla has zlib-ng with
its compatible library, and FreeBSD, NetBSD and OpenBSD have zlib in
their base systems. OpenBSD has no zlib-ng package. The standard API
is on every host.

## Design

**Thin and thick**, as polibfyaml. `ZlibThin` gives zlib's calls,
constants and the `z_stream`; `Zlib` adds ownership, errors and
streams.

**The z_stream lives in C.** `ZlibThin.c` allocates it with
`calloc` and reads and sets its fields through small functions. No
Oberon record mirrors its layout, which differs between zlib and
zlib-ng and between hosts. `deflateInit2` and `inflateInit2` are
macros, so they are called from C too.

**Fixed-width types at the boundary.** `uLong` is 64 bits on LP64
and 32 on i386, so the C part carries counts and checksums as
`int64_t`, and `avail_in`/`avail_out` (`uInt`) are never given more
than `ZlibThin.MaxAvail` (2^30). Writes and checksums cut larger
input into pieces.

**Push streams.** A stream gives its output to a `Sink`, so polout
can write straight into its PDF output without holding a whole page
stream twice. Each stream has a 16 KB output buffer, which zlib's
example also uses.

**Ownership.** Explicit `Close`, idempotent, with a GC finalizer as a
backstop (polibfyaml's "Document ownership"). `OpenStreams` counts
open streams, for tests.

**Errors.** Bad data gives an `Error` (code and message, zlib's
message if it gave one); a failed Inflater keeps its error until
`Reset`. Misuse halts (AGENTS.md, "Halt codes").

**Inflater.Write and what follows the stream.** At the stream's end,
`unused` says how many of the call's bytes were not used, so a
caller can read concatenated gzip members or a stream embedded in
other data. At `NeedDictionary` it says the same for the bytes to
write again after `SetDictionary`.

## Findings (poc 0.15.0, 2026-11-23)

- `SYSTEM.INT64` is not assignable to `LONGINT`, even under `-OC`
  where both have 64 bits; `Zlib.Long` converts with `SYSTEM.VAL`.
- Two separately declared `POINTER TO ARRAY OF CHAR` types are not
  compatible, so the tests use `Zlib.Bytes`.
- The C part's functions can't reuse zlib's names (`adler32`,
  `crc32`), since `<zlib.h>` declares them. They are named `zt_*` in C,
  and `__asm__` gives them the linker names `ZlibThin.-*`.
- An overriding method must be exported if the one it overrides is
  (`Sink.Write`).
- zlib and zlib-ng make different compressed bytes from the same input
  and level. For polout's test documents, zlib 1.4 gave 55,057 bytes
  and zlib-ng 55,201 (polout's PLAN.md, decision 8).
- `deflateSetDictionary` on a gzip stream returns `Z_STREAM_ERROR` in
  both libraries; `Zlib` halts with `AssertOrder`.

## State

**Done (atla, 2026-11-23; poc 0.15.0, zlib-ng-compat 2.3.3):**

- `ZlibThin` and `Zlib`.
- 6 test programs with 105 checks, 9 halt tests and the example: all
  pass under `make test`.
- `make valgrind`: 0 errors, nothing lost, and every still-reachable
  block is the collector's. `TestLiveness` abandons 100 streams, and
  their finalizers free them.

**To do:**

- Test on the six BSD hosts (zlib in each base system). The i386 hosts
  (yishana, cymoril) matter most: their `uLong` has 32 bits.
- `make install` on atla and the hosts, before polout's Phase 11.
- Code 68 (`AssertZlib`) has no halt test: only exhausted memory, a
  mismatched library or a bug in the binding can trigger it.
