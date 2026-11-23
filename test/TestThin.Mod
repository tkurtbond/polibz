MODULE TestThin; (* ZlibThin: constants, version, a raw round trip *)

IMPORT SYSTEM, Zlib, ZlibThin, Check, Hex;

PROCEDURE Constants;
  VAR i: INTEGER; want: ARRAY ZlibThin.Constants OF INTEGER; ok: BOOLEAN;
BEGIN
  want[0] := ZlibThin.Ok; want[1] := ZlibThin.StreamEnd; want[2] := ZlibThin.NeedDict;
  want[3] := ZlibThin.Errno; want[4] := ZlibThin.StreamError; want[5] := ZlibThin.DataError;
  want[6] := ZlibThin.MemError; want[7] := ZlibThin.BufError; want[8] := ZlibThin.VersionError;
  want[9] := ZlibThin.NoFlush; want[10] := ZlibThin.PartialFlush; want[11] := ZlibThin.SyncFlush;
  want[12] := ZlibThin.FullFlush; want[13] := ZlibThin.Finish; want[14] := ZlibThin.Block;
  want[15] := ZlibThin.NoCompression; want[16] := ZlibThin.BestSpeed;
  want[17] := ZlibThin.BestCompression; want[18] := ZlibThin.DefaultCompression;
  want[19] := ZlibThin.Filtered; want[20] := ZlibThin.HuffmanOnly; want[21] := ZlibThin.Rle;
  want[22] := ZlibThin.Fixed; want[23] := ZlibThin.DefaultStrategy;
  want[24] := ZlibThin.MaxWBits; want[25] := ZlibThin.MaxMemLevel;
  ok := TRUE;
  FOR i := 0 TO ZlibThin.Constants - 1 DO
    IF ZlibThin.TestConstant(i) # want[i] THEN ok := FALSE END
  END;
  Check.Check(ok, "every constant is zlib.h's");
  Check.Check(ZlibThin.TestConstant(ZlibThin.Constants) = MIN(SYSTEM.INT32), "the list has no more");
  Check.Check(ZlibThin.MaxAvail <= ZlibThin.UIntMax(), "MaxAvail fits in a uInt")
END Constants;

PROCEDURE Version;
  VAR p: SYSTEM.ADDRESS; c: CHAR;
BEGIN
  p := ZlibThin.ZlibVersion();
  Check.Check(p # 0, "zlibVersion gives a string");
  SYSTEM.GET(p, c);
  Check.Check(c = "1", "the version begins with 1")
END Version;

(* Deflates the test text raw into a buffer of deflateBound bytes in
   one call, inflates it back, and compares. *)
PROCEDURE RoundTrip;
  VAR s: ZlibThin.Stream; text, packed, back: Zlib.Bytes;
    n, bound, m, i: LONGINT; ret: SYSTEM.INT32; ok: BOOLEAN;
BEGIN
  text := Hex.Lout(n);
  s := ZlibThin.StreamNew();
  Check.Check(s # 0, "a new stream");
  ret := ZlibThin.DeflateInit(s, ZlibThin.DefaultCompression, -15, 8, ZlibThin.DefaultStrategy);
  Check.Check(ret = ZlibThin.Ok, "deflateInit2, raw");
  bound := SYSTEM.VAL(LONGINT, ZlibThin.DeflateBound(s, n));
  Check.Check(bound >= n, "deflateBound is at least the input");
  NEW(packed, bound);
  ZlibThin.SetInput(s, SYSTEM.ADR(text[0]), n);
  ZlibThin.SetOutput(s, SYSTEM.ADR(packed[0]), bound);
  ret := ZlibThin.Deflate(s, ZlibThin.Finish);
  Check.Check(ret = ZlibThin.StreamEnd, "one deflate with Finish ends the stream");
  m := SYSTEM.VAL(LONGINT, ZlibThin.TotalOut(s));
  Check.Check((ZlibThin.TotalIn(s) = n) & (m = bound - ZlibThin.AvailOut(s)), "totals agree with avail");
  Check.Check(m < n, "the text compresses");
  ret := ZlibThin.DeflateEnd(s);
  Check.Check(ret = ZlibThin.Ok, "deflateEnd");
  ZlibThin.StreamFree(s);

  s := ZlibThin.StreamNew();
  ret := ZlibThin.InflateInit(s, -15);
  Check.Check(ret = ZlibThin.Ok, "inflateInit2, raw");
  NEW(back, n);
  ZlibThin.SetInput(s, SYSTEM.ADR(packed[0]), m);
  ZlibThin.SetOutput(s, SYSTEM.ADR(back[0]), n);
  ret := ZlibThin.Inflate(s, ZlibThin.Finish);
  Check.Check(ret = ZlibThin.StreamEnd, "inflate reaches the end");
  ok := ZlibThin.TotalOut(s) = n;
  FOR i := 0 TO n - 1 DO IF back[i] # text[i] THEN ok := FALSE END END;
  Check.Check(ok, "the text comes back");
  Check.Check(ZlibThin.Msg(s) = 0, "no message after success");
  ret := ZlibThin.InflateEnd(s);
  ZlibThin.StreamFree(s)
END RoundTrip;

(* A zlib header check that fails: zlib says why. *)
PROCEDURE Message;
  VAR s: ZlibThin.Stream; junk: ARRAY 8 OF CHAR; out: ARRAY 16 OF CHAR; ret: SYSTEM.INT32;
BEGIN
  junk := "garbage";
  s := ZlibThin.StreamNew();
  ret := ZlibThin.InflateInit(s, 15);
  ZlibThin.SetInput(s, SYSTEM.ADR(junk[0]), 7);
  ZlibThin.SetOutput(s, SYSTEM.ADR(out[0]), 16);
  ret := ZlibThin.Inflate(s, ZlibThin.NoFlush);
  Check.Check(ret = ZlibThin.DataError, "junk is a data error");
  Check.Check(ZlibThin.Msg(s) # 0, "with a message");
  ret := ZlibThin.InflateEnd(s);
  ZlibThin.StreamFree(s)
END Message;

BEGIN
  Constants; Version; RoundTrip; Message;
  Check.Summary
END TestThin.
