MODULE TestRoundTrip; (* Compress and Uncompress in every format and level; fixed vectors *)

IMPORT Zlib, Check, Hex;

(* The test text through Compress and back, at every level. *)
PROCEDURE Levels(format: INTEGER; name: ARRAY OF CHAR);
  VAR text: Zlib.Bytes; packed, back: Zlib.Buffer; err: Zlib.Error;
    n: LONGINT; level: INTEGER; ok, smaller: BOOLEAN;
BEGIN
  text := Hex.Lout(n); ok := TRUE; smaller := TRUE;
  FOR level := Zlib.DefaultCompression TO Zlib.BestCompression DO
    packed := Zlib.Compress(text^, 0, n, level, format);
    IF (level # Zlib.NoCompression) & (packed.len >= n) THEN smaller := FALSE END;
    IF ~Zlib.Uncompress(packed.data^, 0, packed.len, format, back, err)
       OR ~Hex.Same(back, text^, n) THEN ok := FALSE
    END
  END;
  Check.Check(ok, name);
  Check.Check(smaller, "  and compresses at every level but 0")
END Levels;

(* Streams made by another program (Python's zlib module), each
   checked against the text they were made from. *)
PROCEDURE Vector(hex: ARRAY OF CHAR; format: INTEGER; name: ARRAY OF CHAR);
  VAR text, packed: Zlib.Bytes; back: Zlib.Buffer; err: Zlib.Error; n, m: LONGINT;
BEGIN
  text := Hex.Lout(n); packed := Hex.Bytes(hex, m);
  Check.Check(Zlib.Uncompress(packed^, 0, m, format, back, err) & Hex.Same(back, text^, n), name)
END Vector;

PROCEDURE Vectors;
  CONST
    zlib = "78daf3c92f2d51c82c56485448c94f2ecd4dcd2b5148cb2fca4d2c29c9cc4b5728ae2c2e49cdd5e3f2a1a22a006cd529e9";
    gzip = "1f8b0800000000000203f3c92f2d51c82c56485448c94f2ecd4dcd2b5148cb2fca4d2c29c9cc4b5728ae2c2e49cdd5e3f2a1a22a00c69b137f72000000";
    raw = "f3c92f2d51c82c56485448c94f2ecd4dcd2b5148cb2fca4d2c29c9cc4b5728ae2c2e49cdd5e3f2a1a22a00";
BEGIN
  Vector(zlib, Zlib.ZlibFormat, "a zlib stream from elsewhere");
  Vector(gzip, Zlib.GzipFormat, "a gzip stream from elsewhere");
  Vector(raw, Zlib.RawFormat, "a raw stream from elsewhere");
  Vector(zlib, Zlib.AnyFormat, "AnyFormat reads zlib");
  Vector(gzip, Zlib.AnyFormat, "AnyFormat reads gzip")
END Vectors;

(* The two-byte zlib header and gzip's magic, which PDF and gzip
   readers look for. *)
PROCEDURE Headers;
  VAR text: Zlib.Bytes; z, g: Zlib.Buffer; n: LONGINT;
BEGIN
  text := Hex.Lout(n);
  z := Zlib.Compress(text^, 0, n, Zlib.DefaultCompression, Zlib.ZlibFormat);
  Check.Check((ORD(z.data[0]) MOD 16 = 8) & ((ORD(z.data[0]) * 256 + ORD(z.data[1])) MOD 31 = 0),
    "a zlib header: deflate, and a valid check");
  g := Zlib.Compress(text^, 0, n, Zlib.DefaultCompression, Zlib.GzipFormat);
  Check.Check((ORD(g.data[0]) = 1FH) & (ORD(g.data[1]) = 8BH), "gzip's magic number")
END Headers;

(* Nothing, and part of a buffer. *)
PROCEDURE Edges;
  VAR text: Zlib.Bytes; packed, back: Zlib.Buffer; err: Zlib.Error; n: LONGINT;
    empty: ARRAY 1 OF CHAR;
BEGIN
  packed := Zlib.Compress(empty, 0, 0, Zlib.DefaultCompression, Zlib.ZlibFormat);
  Check.Check(packed.len > 0, "nothing compresses to a stream");
  Check.Check(Zlib.Uncompress(packed.data^, 0, packed.len, Zlib.ZlibFormat, back, err)
    & (back.len = 0), "and decompresses to nothing");
  text := Hex.Lout(n);
  (* The second line alone: bytes 38 to 75. *)
  packed := Zlib.Compress(text^, 38, 38, Zlib.BestCompression, Zlib.RawFormat);
  Check.Check(Zlib.Uncompress(packed.data^, 0, packed.len, Zlib.RawFormat, back, err)
    & (back.len = 38) & (back.data[0] = "L") & (back.data[37] = 0AX), "part of a buffer")
END Edges;

(* A megabyte, so the output fills the 16 KB buffer many times. *)
PROCEDURE Large;
  CONST size = 1048576;
  VAR text: Zlib.Bytes; packed, back: Zlib.Buffer; err: Zlib.Error;
BEGIN
  text := Hex.Sample(size);
  packed := Zlib.Compress(text^, 0, size, Zlib.DefaultCompression, Zlib.GzipFormat);
  Check.Check(packed.len > 65536, "a megabyte makes many chunks of output");
  Check.Check(Zlib.Uncompress(packed.data^, 0, packed.len, Zlib.GzipFormat, back, err)
    & Hex.Same(back, text^, size), "and comes back whole")
END Large;

BEGIN
  Levels(Zlib.ZlibFormat, "zlib format at every level round trips");
  Levels(Zlib.GzipFormat, "gzip format at every level round trips");
  Levels(Zlib.RawFormat, "raw format at every level round trips");
  Vectors; Headers; Edges; Large;
  Check.Summary
END TestRoundTrip.
