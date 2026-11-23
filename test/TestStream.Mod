MODULE TestStream; (* Deflater and Inflater as streams: pieces, Flush, Reset, sinks *)

IMPORT Zlib, Check, Hex;

TYPE
  (* A sink that counts its calls and bytes, keeping nothing. *)
  Counter = POINTER TO CounterDesc;
  CounterDesc = RECORD (Zlib.SinkDesc)
    calls, bytes: LONGINT
  END;

PROCEDURE (c: Counter) Write*(VAR buf: ARRAY OF CHAR; n: LONGINT);
BEGIN INC(c.calls); INC(c.bytes, n)
END Write;

(* The text written a byte at a time compresses to what decompresses
   to the text, and is read back a byte at a time. *)
PROCEDURE SmallPieces;
  CONST size = 5000;
  VAR text: Zlib.Bytes; packed, back: Zlib.Buffer; d: Zlib.Deflater; i: Zlib.Inflater;
    err: Zlib.Error; k: LONGINT; ok: BOOLEAN;
BEGIN
  text := Hex.Sample(size);
  packed := Zlib.NewBuffer(); d := Zlib.NewDeflater(packed, Zlib.DefaultCompression, Zlib.ZlibFormat);
  FOR k := 0 TO size - 1 DO d.Write(text^, k, 1) END;
  d.Finish;
  Check.Check(d.TotalIn() = size, "TotalIn counts what was written");
  Check.Check(d.TotalOut() = packed.len, "TotalOut counts what the sink got");
  d.Close;
  back := Zlib.NewBuffer(); i := Zlib.NewInflater(back, Zlib.ZlibFormat);
  ok := TRUE; k := 0;
  WHILE ok & (k < packed.len) & ~i.Ended() DO ok := i.Write(packed.data^, k, 1, err); INC(k) END;
  Check.Check(ok & i.Ended() & (k = packed.len), "read a byte at a time, the stream ends at its last byte");
  Check.Check(i.Finish(err) & (err = NIL), "and Finish agrees");
  Check.Check(Hex.Same(back, text^, size), "written a byte at a time, comes back whole");
  Check.Check((i.TotalIn() = packed.len) & (i.TotalOut() = size), "the Inflater's totals");
  i.Close
END SmallPieces;

(* After Flush, what the sink has decompresses to everything written,
   though the stream goes on. *)
PROCEDURE Flushing;
  CONST size = 3000; half = 1700;
  VAR text: Zlib.Bytes; packed, back: Zlib.Buffer; d: Zlib.Deflater; i: Zlib.Inflater;
    err: Zlib.Error; first: LONGINT; ok: BOOLEAN;
BEGIN
  text := Hex.Sample(size);
  packed := Zlib.NewBuffer(); d := Zlib.NewDeflater(packed, Zlib.BestCompression, Zlib.GzipFormat);
  d.Write(text^, 0, half); d.Flush; first := packed.len;
  back := Zlib.NewBuffer(); i := Zlib.NewInflater(back, Zlib.GzipFormat);
  ok := i.Write(packed.data^, 0, first, err);
  Check.Check(ok & ~i.Ended() & Hex.Same(back, text^, half), "after Flush, the first part decompresses");
  d.Flush;
  Check.Check(packed.len - first <= 5, "a second Flush with nothing new adds at most an empty block");
  d.Write(text^, half, size - half); d.Finish; d.Close;
  ok := i.Write(packed.data^, first, packed.len - first, err);
  Check.Check(ok & i.Ended() & (i.unused = 0) & Hex.Same(back, text^, size), "and the rest follows");
  i.Close
END Flushing;

(* Reset starts a new stream, with the same settings, to a new sink. *)
PROCEDURE Resetting;
  VAR text: Zlib.Bytes; a, b, back: Zlib.Buffer; d: Zlib.Deflater; i: Zlib.Inflater;
    err: Zlib.Error; n: LONGINT; ok: BOOLEAN;
BEGIN
  text := Hex.Lout(n);
  a := Zlib.NewBuffer(); d := Zlib.NewDeflater(a, Zlib.BestSpeed, Zlib.RawFormat);
  d.Write(text^, 0, 50);  (* dropped by Reset *)
  b := Zlib.NewBuffer(); d.Reset(b);
  Check.Check(d.TotalIn() = 0, "Reset clears the totals");
  d.Write(text^, 0, n); d.Finish;
  Check.Check(Zlib.Uncompress(b.data^, 0, b.len, Zlib.RawFormat, back, err) & Hex.Same(back, text^, n),
    "a Deflater reset to a new sink makes a whole new stream");
  b.Clear; d.Reset(b); d.Write(text^, 38, 38); d.Finish; d.Close;
  back := Zlib.NewBuffer(); i := Zlib.NewInflater(back, Zlib.RawFormat);
  ok := i.Write(b.data^, 0, b.len, err) & i.Finish(err);
  Check.Check(ok & (back.len = 38), "a cleared Buffer takes a new stream");
  back.Clear; i.Reset(back);
  ok := Zlib.Uncompress(b.data^, 0, b.len, Zlib.RawFormat, a, err);
  ok := i.Write(b.data^, 0, b.len, err) & i.Finish(err);
  Check.Check(ok & (back.len = 38) & Hex.Same(back, a.data^, a.len), "an Inflater reset reads another stream");
  i.Close
END Resetting;

(* A plain Sink measures; an extended one sees each piece. *)
PROCEDURE Sinks;
  CONST size = 200000;
  VAR text: Zlib.Bytes; s: Zlib.Sink; c: Counter; d: Zlib.Deflater; packed: Zlib.Buffer;
    i: Zlib.Inflater; err: Zlib.Error; measured: LONGINT;
BEGIN
  text := Hex.Sample(size);
  NEW(s); d := Zlib.NewDeflater(s, Zlib.DefaultCompression, Zlib.ZlibFormat);
  Check.Check(d.Bound(size) >= size, "Bound allows for data that does not compress");
  d.Write(text^, 0, size); d.Finish; measured := d.TotalOut(); d.Close;
  packed := Zlib.Compress(text^, 0, size, Zlib.DefaultCompression, Zlib.ZlibFormat);
  Check.Check(measured = packed.len, "a plain Sink measures what a Buffer would hold");
  NEW(c); c.calls := 0; c.bytes := 0;
  i := Zlib.NewInflater(c, Zlib.AnyFormat);
  Check.Check(i.Write(packed.data^, 0, packed.len, err) & i.Finish(err), "an extended Sink takes the output");
  Check.Check((c.bytes = size) & (c.calls >= size DIV 16384), "in pieces no bigger than the stream's buffer");
  i.Close
END Sinks;

(* Every window size, memory level and strategy round trips. *)
PROCEDURE Settings;
  CONST size = 40000;
  VAR text: Zlib.Bytes; packed, back: Zlib.Buffer; d: Zlib.Deflater; err: Zlib.Error;
    bits, mem, strategy, format: INTEGER; ok: BOOLEAN;
BEGIN
  text := Hex.Sample(size); ok := TRUE;
  FOR format := Zlib.ZlibFormat TO Zlib.RawFormat DO
    FOR bits := 9 TO 15 DO
      FOR mem := 1 TO 9 BY 4 DO
        FOR strategy := Zlib.DefaultStrategy TO Zlib.Fixed DO
          packed := Zlib.NewBuffer();
          d := Zlib.NewDeflaterWith(packed, Zlib.DefaultCompression, format, bits, mem, strategy);
          d.Write(text^, 0, size); d.Finish; d.Close;
          IF ~Zlib.Uncompress(packed.data^, 0, packed.len, format, back, err)
             OR ~Hex.Same(back, text^, size) THEN ok := FALSE
          END
        END
      END
    END
  END;
  Check.Check(ok, "every window, memory level and strategy, in every format, round trips")
END Settings;

(* A preset dictionary, both ways, and a stream made elsewhere with
   one. *)
PROCEDURE Dictionary;
  CONST vector = "78f98d300a80f3c92f2d51c82c56485448c1a9468f8b9aaa006cd529e9";
  VAR text, dict, v: Zlib.Bytes; packed, plain, back: Zlib.Buffer; d: Zlib.Deflater; i: Zlib.Inflater;
    err: Zlib.Error; n, dn, vn, k: LONGINT; ok: BOOLEAN;
BEGIN
  text := Hex.Lout(n); dict := Hex.Text("document formatting system", dn);
  packed := Zlib.NewBuffer(); d := Zlib.NewDeflater(packed, Zlib.BestCompression, Zlib.ZlibFormat);
  d.SetDictionary(dict^, 0, dn); d.Write(text^, 0, n); d.Finish; d.Close;
  plain := Zlib.Compress(text^, 0, n, Zlib.BestCompression, Zlib.ZlibFormat);
  Check.Check(packed.len < plain.len, "a good dictionary makes the stream smaller");
  v := Hex.Bytes(vector, vn);
  FOR k := 0 TO 1 DO
    IF k = 1 THEN packed.Clear; packed.Write(v^, vn) END;
    back := Zlib.NewBuffer(); i := Zlib.NewInflater(back, Zlib.ZlibFormat);
    ok := i.Write(packed.data^, 0, packed.len, err);
    Check.Check(~ok & (err.code = Zlib.NeedDictionary) & (i.unused > 0) & (i.unused < packed.len),
      "the Inflater asks for the dictionary");
    Check.Check(i.SetDictionary(dict^, 0, dn, err) & (err = NIL), "and takes it");
    ok := i.Write(packed.data^, packed.len - i.unused, i.unused, err) & i.Finish(err);
    IF k = 0 THEN Check.Check(ok & Hex.Same(back, text^, n), "then reads the rest")
    ELSE Check.Check(ok & Hex.Same(back, text^, n), "a stream made elsewhere with a dictionary")
    END;
    i.Close
  END
END Dictionary;

BEGIN
  SmallPieces; Flushing; Resetting; Sinks; Settings; Dictionary;
  Check.Summary
END TestStream.
