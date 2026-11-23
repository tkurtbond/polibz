# polibz - an Oberon binding to zlib for poc

polibz lets Oberon-2 programs compiled with poc, the Peaseblossom
Oberon Compiler, compress and decompress data with zlib: deflate
streams in the zlib (RFC 1950), gzip (RFC 1952) and raw (RFC 1951)
formats, with Adler-32 and CRC-32. It uses zlib's standard API, so it
links with zlib or with zlib-ng's compatible library.

BSD 3-Clause licence (LICENSE).

## Requirements

- poc 0.15.0 or later.
- zlib's header and library where the C compiler finds them: on Fedora
  `zlib-ng-compat-devel`; on FreeBSD, NetBSD and OpenBSD the base
  system's.
- GNU make.

## Building and testing

```sh
make test         # gmake on the BSDs
make valgrind     # where valgrind is installed
make install      # into ~/.local/lib/poc (POCLIBDIR)
```

## Using it

Compile with `-OC` and `-library-path ~/.local/lib/poc`, and import
`Zlib`. No flags for zlib are needed: the library records them.

```oberon
VAR packed, back: Zlib.Buffer; err: Zlib.Error;
...
packed := Zlib.Compress(text, 0, n, Zlib.BestCompression, Zlib.ZlibFormat);
IF Zlib.Uncompress(packed.data^, 0, packed.len, Zlib.ZlibFormat, back, err) THEN
  (* back.data[0 .. back.len-1] is the text again *)
ELSE
  Out.String(err.message)
END
```

For streams, a `Deflater` takes bytes through `Write` and gives what
it makes to a `Sink`; `Flush` and `Finish` push out the rest. An
`Inflater` does the reverse. A `Buffer` is a `Sink` that keeps
everything; extend `Zlib.SinkDesc` and override `Write` to send the
output elsewhere, such as a file.

```oberon
buf := Zlib.NewBuffer();
d := Zlib.NewDeflater(buf, Zlib.DefaultCompression, Zlib.GzipFormat);
d.Write(part1, 0, n1); d.Write(part2, 0, n2); d.Finish; d.Close
```

Close every stream: it owns zlib's state, which the collector can't
see. A finalizer closes an unreachable one, but only when a collection
runs.

Bad compressed data is a result, not a halt: `Inflater.Write`,
`Inflater.Finish` and `Uncompress` return FALSE with an `Error`
(`DataError`, `NeedDictionary`, `Truncated`, `DictionaryError`,
`TrailingData`). Misuse, such as writing to a closed stream or passing
a slice past an array's end, halts with an `Assert` code from 66 to
69.

zlib and zlib-ng make different compressed bytes from the same
input. Both are valid and decompress the same, but compare
decompressed data, not compressed.

`examples/ExampleRoundTrip.Mod` is a complete program.

## Layout

- `src/ZlibThin.Mod`, `src/ZlibThin.c`: the thin layer over zlib.
- `src/Zlib.Mod`: the binding.
- `test/`, `examples/`: tests and the example.
