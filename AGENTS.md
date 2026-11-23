# AGENTS.md

Oberon-2 binding to zlib, compiled with poc, the Peaseblossom Oberon
Compiler. It binds zlib's standard API (deflate and inflate in the
zlib, gzip and raw formats, Adler-32 and CRC-32), so it works with
zlib itself and with zlib-ng's compatible library alike. It was made
for polout (`~/Repos/Oberon/polout`, its decision 13), whose PDF
back end compresses with it, but is a library of its own. PLAN.md is
the design; this file is operational notes.

Its form is polibfyaml's (`~/Repos/Oberon/polibfyaml`): a thin module
with a part in C, a thick module with the ownership and error policy,
`Check`-style tests, halt tests, examples, valgrind with the
collector's suppressions, and `make install` into `POCLIBDIR`. Read
polibfyaml's AGENTS.md before changing any of that.

## Reference material

| What | Where |
|---|---|
| zlib's API | `/usr/include/zlib.h` (atla: zlib-ng-compat-devel 2.3.3, `ZLIB_VERSION` "1.3.1.zlib-ng"); zlib's manual, <https://zlib.net/manual.html> |
| zlib source (1.4, unused by the build) | `/usr/local/sw/src/doctools/lout-2023_06_19/zlib` |
| poc | `/usr/bin/poc` (0.15.0 on 2026-11-23); `~/Repos/Oberon/Peaseblossom/doc/` |
| The model binding | `~/Repos/Oberon/polibfyaml` |

## Build

`GNUmakefile`, so `make` on atla and `gmake` on the BSDs:

```sh
make            # test programs, halt tests and the example, into build/
make test       # run them all
make valgrind   # the test programs under valgrind
make install    # the library polibz (-OC, with and without -g) into POCLIBDIR
make uninstall
make clean
```

The library is built in `build/lib` and the tests take it from there.
`src/ZlibThin.c`, beside `ZlibThin.Mod`, is compiled by poc with clang
as ZlibThin's part in C. `-link -lz` is recorded in the library, so a
program using it passes no flags for zlib. `ZLIB_LIBS` and
`ZLIB_CFLAGS` are for a zlib outside the compiler's search paths;
there is no pkg-config, as OpenBSD's base zlib has no `.pc` file.

Size model: **`-OC` only**, as polibfyaml and polout. In `ZlibThin`
every C-boundary type has an explicit size (`SYSTEM.INT32` for an
`int`, `SYSTEM.INT64` for a count or `uLong`, `SYSTEM.ADDRESS` for a
pointer); `Zlib` uses `INTEGER` and `LONGINT`.

## Test

- Test programs (`test/Test*.Mod`, listed in `TESTS`) print
  `ok   - `/`FAIL - ` through `test/Check.Mod`; `test/Hex.Mod` has the
  shared data (bytes from hex, the test text, a sample generator).
- Halt tests (`test/Halt*.Mod`, `HALTTESTS` as `name:code`): poc's
  `ASSERT(x, n)` prints `assertion failed (n)` and exits with 10, and
  `make test` checks both.
- `examples/ExampleRoundTrip` must print exactly its `.expected`.
- **Compressed bytes differ between zlib and zlib-ng** (and between
  zlib versions), so no test compares what a Deflater makes with fixed
  bytes. Tests check that it decompresses to the input, and fixed
  vectors (made with Python's zlib) are read by the Inflater only.
  The example prints nothing that depends on the library.
- `make valgrind` must show 0 errors and nothing lost, and
  `test/vg-reachable.sh` requires every still-reachable block to be
  the collector's: a zlib stream never freed is reachable from the
  Oberon heap, so it shows as still reachable, not lost. Cap the run
  (`systemd-run --user --scope -p MemoryMax=8G -p MemorySwapMax=0`);
  it needs well under 1 GB.

On the BSD hosts (polout's AGENTS.md lists them): copy the tree to
`~/tmp`, `gmake test`, judge by the exit status and by counting `FAIL`
and `assertion failed` lines, then remove it. Not yet done (PLAN.md).

## Layout

- `src/ZlibThin.Mod`, `src/ZlibThin.c`: zlib's calls, constants and
  the `z_stream` (allocated and read in C, so no Oberon record mirrors
  its layout). No policy.
- `src/Zlib.Mod`: `Sink`, `Buffer`, `Deflater`, `Inflater`, `Error`,
  `Compress`, `Uncompress`, `Adler32`, `Crc32`, `Version`.
- `test/`, `examples/`: as above.

## Halt codes

The po* libraries share the range 61 to 99. polibz has 66 to 69:

| Code | Name | Meaning |
|---|---|---|
| 66 | `AssertClosed` | the stream has been closed |
| 67 | `AssertRange` | an argument out of range, or a NIL sink |
| 68 | `AssertZlib` | zlib refused: out of memory, a mismatched library, or a bug in the binding |
| 69 | `AssertOrder` | a call at the wrong point in the stream's life |

68 has no halt test: a correct binding can't trigger it.

## Conventions

- **Claim only what has been verified**, with the date and versions.
- Programmer errors halt; bad compressed data is an `Error` result.
- Comments explain why.
- Throwaway work goes under `/usr/local/sw/tmp`, never `/tmp`.
- Commit only when asked.
