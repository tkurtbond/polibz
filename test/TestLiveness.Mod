MODULE TestLiveness; (* Closing, finalizers, and buffers that outlive their streams *)

(* zlib's state is C memory, which only Close or the finalizer frees.
   Zlib.OpenStreams counts what is still open. The "halts after
   Close" cases are separate programs (HaltClosed, HaltInflaterClosed),
   run by `make test` expecting a halt. *)

IMPORT GarbageCollectedHeap, Zlib, Check, Hex;

TYPE Junk = POINTER TO ARRAY OF CHAR;

(* Allocates and drops garbage, then collects, so freed memory is
   reused. *)
PROCEDURE Churn;
  VAR i, k: INTEGER; j: Junk;
BEGIN
  GarbageCollectedHeap.Collect;
  FOR i := 1 TO 2000 DO
    NEW(j, 8 + i MOD 2000);
    FOR k := 0 TO SHORT(LEN(j^)) - 1 DO j[k] := "x" END
  END;
  GarbageCollectedHeap.Collect
END Churn;

(* Makes streams and drops them unclosed. *)
PROCEDURE Abandon(count: INTEGER);
  VAR k: INTEGER; d: Zlib.Deflater; i: Zlib.Inflater; text: Zlib.Bytes; n: LONGINT;
BEGIN
  text := Hex.Lout(n);
  FOR k := 1 TO count DO
    d := Zlib.NewDeflater(Zlib.NewBuffer(), Zlib.DefaultCompression, Zlib.ZlibFormat);
    d.Write(text^, 0, n);
    i := Zlib.NewInflater(Zlib.NewBuffer(), Zlib.AnyFormat)
  END
END Abandon;

PROCEDURE Closing;
  VAR d: Zlib.Deflater; i: Zlib.Inflater; s: Zlib.Sink; before: LONGINT; a: ARRAY 4 OF CHAR;
BEGIN
  before := Zlib.OpenStreams();
  NEW(s); d := Zlib.NewDeflater(s, Zlib.DefaultCompression, Zlib.ZlibFormat);
  i := Zlib.NewInflater(s, Zlib.ZlibFormat);
  Check.Check(Zlib.OpenStreams() = before + 2, "each new stream is counted open");
  Check.Check(~d.Closed() & ~i.Closed(), "and is not closed");
  d.Close; i.Close;
  Check.Check(d.Closed() & i.Closed() & (Zlib.OpenStreams() = before), "Close closes");
  d.Close; i.Close;
  Check.Check(Zlib.OpenStreams() = before, "Close again does nothing");
  d := Zlib.NewDeflater(s, Zlib.DefaultCompression, Zlib.ZlibFormat);
  a := "abc"; d.Write(a, 0, 3); d.Close;
  Check.Check(Zlib.OpenStreams() = before, "an unfinished stream closes too")
END Closing;

PROCEDURE Finalizing;
  CONST count = 50;
  VAR before: LONGINT;
BEGIN
  before := Zlib.OpenStreams();
  (* The collector may run while Abandon allocates, so some may be
     closed already. *)
  Abandon(count);
  Churn; Churn;
  (* The collector scans the stack conservatively, so a stale pointer
     may keep the last stream or two alive. *)
  Check.Check(Zlib.OpenStreams() <= before + 2, "the collector's finalizers close them")
END Finalizing;

(* A Buffer from Compress outlives its stream, and keeps its bytes
   through collections. *)
PROCEDURE Outliving;
  CONST size = 100000;
  VAR text: Zlib.Bytes; packed, back: Zlib.Buffer; err: Zlib.Error;
BEGIN
  text := Hex.Sample(size);
  packed := Zlib.Compress(text^, 0, size, Zlib.DefaultCompression, Zlib.ZlibFormat);
  Churn;
  Check.Check(Zlib.Uncompress(packed.data^, 0, packed.len, Zlib.ZlibFormat, back, err), "a Buffer outlives its stream");
  Churn;
  Check.Check(Hex.Same(back, text^, size), "and keeps its bytes through collections")
END Outliving;

BEGIN
  Closing; Finalizing; Outliving;
  Check.Check(Zlib.OpenStreams() <= 2, "nothing left open but what the stack may hold");
  Check.Summary
END TestLiveness.
