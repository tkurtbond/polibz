MODULE TestErrors; (* Bad compressed data: corrupt, truncated, trailing, wrong format, dictionaries *)

IMPORT Zlib, Check, Hex;

CONST
  zlib = "78daf3c92f2d51c82c56485448c94f2ecd4dcd2b5148cb2fca4d2c29c9cc4b5728ae2c2e49cdd5e3f2a1a22a006cd529e9";
  gzip = "1f8b0800000000000203f3c92f2d51c82c56485448c94f2ecd4dcd2b5148cb2fca4d2c29c9cc4b5728ae2c2e49cdd5e3f2a1a22a00c69b137f72000000";
  raw = "f3c92f2d51c82c56485448c94f2ecd4dcd2b5148cb2fca4d2c29c9cc4b5728ae2c2e49cdd5e3f2a1a22a00";
  withDict = "78f98d300a80f3c92f2d51c82c56485448c1a9468f8b9aaa006cd529e9";

(* Uncompress fails with code, out NIL and a message. *)
PROCEDURE Fails(VAR data: ARRAY OF CHAR; n: LONGINT; format, code: INTEGER; name: ARRAY OF CHAR);
  VAR out: Zlib.Buffer; err: Zlib.Error; ok: BOOLEAN;
BEGIN
  ok := Zlib.Uncompress(data, 0, n, format, out, err);
  Check.Check(~ok & (out = NIL) & (err # NIL) & (err.code = code) & (err.message[0] # 0X), name)
END Fails;

PROCEDURE Corrupt;
  VAR b: Zlib.Bytes; n: LONGINT;
BEGIN
  b := Hex.Bytes(zlib, n);
  b[n - 1] := CHR((ORD(b[n - 1]) + 1) MOD 256);
  Fails(b^, n, Zlib.ZlibFormat, Zlib.DataError, "a wrong Adler-32 is a DataError");
  b := Hex.Bytes(gzip, n);
  b[n - 8] := CHR((ORD(b[n - 8]) + 1) MOD 256);
  Fails(b^, n, Zlib.GzipFormat, Zlib.DataError, "a wrong CRC-32 is a DataError");
  b := Hex.Bytes(gzip, n);
  b[n - 4] := CHR((ORD(b[n - 4]) + 1) MOD 256);
  Fails(b^, n, Zlib.GzipFormat, Zlib.DataError, "a wrong gzip length is a DataError");
  b := Hex.Bytes("ffffffffffffffff", n);
  Fails(b^, n, Zlib.RawFormat, Zlib.DataError, "junk is a DataError")
END Corrupt;

PROCEDURE WrongFormat;
  VAR b: Zlib.Bytes; n: LONGINT;
BEGIN
  b := Hex.Bytes(zlib, n);
  Fails(b^, n, Zlib.GzipFormat, Zlib.DataError, "zlib read as gzip is a DataError");
  b := Hex.Bytes(gzip, n);
  Fails(b^, n, Zlib.ZlibFormat, Zlib.DataError, "gzip read as zlib is a DataError");
  b := Hex.Bytes(raw, n);
  Fails(b^, n, Zlib.AnyFormat, Zlib.DataError, "raw read as AnyFormat is a DataError")
END WrongFormat;

PROCEDURE Truncation;
  VAR b: Zlib.Bytes; n: LONGINT; back: Zlib.Buffer; i: Zlib.Inflater; err: Zlib.Error; ok: BOOLEAN;
BEGIN
  b := Hex.Bytes(zlib, n);
  Fails(b^, n - 1, Zlib.ZlibFormat, Zlib.Truncated, "a stream cut short is Truncated");
  Fails(b^, 1, Zlib.ZlibFormat, Zlib.Truncated, "half a header is Truncated");
  Fails(b^, 0, Zlib.ZlibFormat, Zlib.Truncated, "nothing at all is Truncated");
  back := Zlib.NewBuffer(); i := Zlib.NewInflater(back, Zlib.ZlibFormat);
  ok := i.Write(b^, 0, n DIV 2, err);
  Check.Check(ok & (err = NIL) & ~i.Ended(), "half a stream is no error while more may come");
  Check.Check(~i.Finish(err) & (err.code = Zlib.Truncated), "but Finish says Truncated");
  i.Close
END Truncation;

(* Bytes after the end: Uncompress refuses them; the Inflater stops at
   the end and says how many it did not use. *)
PROCEDURE Trailing;
  VAR one, two: Zlib.Bytes; n, m, k, j: LONGINT; back, b2: Zlib.Buffer; i: Zlib.Inflater;
    err: Zlib.Error; text: Zlib.Bytes; t: LONGINT; ok: BOOLEAN;
BEGIN
  one := Hex.Bytes(gzip, n);
  (* Two gzip members, as cat makes. *)
  NEW(two, 2 * n); m := 2 * n;
  FOR k := 0 TO n - 1 DO two[k] := one[k]; two[n + k] := one[k] END;
  Fails(two^, m, Zlib.GzipFormat, Zlib.TrailingData, "a second member is TrailingData to Uncompress");
  text := Hex.Lout(t);
  back := Zlib.NewBuffer(); i := Zlib.NewInflater(back, Zlib.GzipFormat);
  ok := i.Write(two^, 0, m, err);
  Check.Check(ok & i.Ended() & (i.unused = n) & Hex.Same(back, text^, t),
    "the Inflater stops after the first member, leaving the second unused");
  k := m - i.unused;  (* before Reset, which clears unused *)
  b2 := Zlib.NewBuffer(); i.Reset(b2);
  ok := i.Write(two^, k, n, err);
  Check.Check(ok & i.Ended() & (i.unused = 0) & Hex.Same(b2, text^, t), "and after Reset reads the second");
  (* Pieces that straddle the end. *)
  back.Clear; i.Reset(back); k := 0;
  WHILE ~i.Ended() DO
    IF m - k < 10 THEN j := m - k ELSE j := 10 END;
    ok := i.Write(two^, k, j, err); INC(k, j)
  END;
  Check.Check(ok & (k - i.unused = n) & Hex.Same(back, text^, t), "unused counts back from the last piece's end");
  i.Close
END Trailing;

PROCEDURE Spent;
  VAR b: Zlib.Bytes; n: LONGINT; back: Zlib.Buffer; i: Zlib.Inflater; err, first: Zlib.Error; ok: BOOLEAN;
BEGIN
  b := Hex.Bytes(zlib, n); b[5] := 0FFX; b[6] := 0FFX; b[7] := 0FFX;
  back := Zlib.NewBuffer(); i := Zlib.NewInflater(back, Zlib.ZlibFormat);
  ok := i.Write(b^, 0, n, first);
  Check.Check(~ok & (first.code = Zlib.DataError), "corrupt data stops the stream");
  ok := i.Write(b^, 0, n, err);
  Check.Check(~ok & (err = first), "every later Write gives the same error");
  Check.Check(~i.Finish(err) & (err = first), "and so does Finish");
  b := Hex.Bytes(zlib, n); back.Clear; i.Reset(back);
  Check.Check(i.Write(b^, 0, n, err) & i.Finish(err), "until Reset");
  i.Close
END Spent;

PROCEDURE Dictionaries;
  VAR b, dict, wrong: Zlib.Bytes; n, dn, wn, at: LONGINT; back: Zlib.Buffer; i: Zlib.Inflater;
    err: Zlib.Error; ok: BOOLEAN;
BEGIN
  b := Hex.Bytes(withDict, n);
  Fails(b^, n, Zlib.ZlibFormat, Zlib.NeedDictionary, "Uncompress cannot give a dictionary");
  dict := Hex.Text("document formatting system", dn);
  wrong := Hex.Text("something else entirely", wn);
  back := Zlib.NewBuffer(); i := Zlib.NewInflater(back, Zlib.ZlibFormat);
  ok := i.Write(b^, 0, n, err);
  Check.Check(~ok & (err.code = Zlib.NeedDictionary), "NeedDictionary");
  at := n - i.unused;
  ok := i.Write(b^, at, n - at, err);
  Check.Check(~ok & (err.code = Zlib.NeedDictionary), "and Write keeps asking until it is given");
  Check.Check(~i.SetDictionary(wrong^, 0, wn, err) & (err.code = Zlib.DictionaryError),
    "the wrong dictionary is a DictionaryError");
  Check.Check(i.SetDictionary(dict^, 0, dn, err), "the right one is then accepted");
  Check.Check(i.Write(b^, at, n - at, err) & i.Finish(err), "and the stream reads");
  i.Close
END Dictionaries;

BEGIN
  Corrupt; WrongFormat; Truncation; Trailing; Spent; Dictionaries;
  Check.Summary
END TestErrors.
