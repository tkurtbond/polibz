MODULE Zlib; (* Oberon-2 binding to zlib: deflate and inflate streams, checksums *)

(* Copyright (c) 2026, T. Kurt Bond. BSD 3-Clause License; see LICENSE.

   Compress and decompress in zlib's three formats (zlib, gzip and raw
   deflate) and compute Adler-32 and CRC-32, through zlib's standard
   API: zlib itself, or zlib-ng's compatible library.

   Streams push. A Deflater takes bytes through Write and gives what it
   makes to a Sink, an object whose Write method the caller supplies
   by extending SinkDesc; Flush and Finish push out the rest. An
   Inflater is the same the other way round. Buffer is a Sink that
   keeps everything in memory. Compress and Uncompress do it all in
   one call.

   Bytes are CHARs: data is ARRAY OF CHAR, with a start position and a
   count, so part of a buffer can be passed without copying, and a 0X
   is a byte like any other.

   Compressed bytes depend on the library. zlib and zlib-ng make
   different, equally valid, deflate streams from the same input and
   level, so compare what decompresses, not what compresses, unless
   both sides link the same library.

   Ownership. A stream owns zlib's state, which is C memory. Close it
   when done: Close is idempotent, and a GC finalizer closes any stream
   that becomes unreachable without one -- but the GC runs only when
   Oberon code allocates and cannot see zlib's memory (about 256 KB
   for each Deflater at the default settings), so don't rely on it for
   streams made in a loop. Reset makes a stream ready for new data
   without freeing it.

   Errors. Bad compressed data is an ordinary result: Inflater.Write,
   Inflater.Finish and Uncompress return FALSE and hand back an Error
   in a VAR parameter (NIL on success). Programmer errors -- a closed
   stream, an argument out of range, a call in the wrong order -- halt
   with one of the Assert codes below (poc prints "assertion failed
   (66)" on standard error and exits with status 10). So does a zlib
   result that only a bug in this binding, a mismatched library or
   exhausted memory can cause (AssertZlib), as NEW halts when memory
   runs out. *)

IMPORT SYSTEM, GarbageCollectedHeap, ZlibThin;

CONST
  (* Levels: 0 to 9, or DefaultCompression (zlib's 6) *)
  DefaultCompression* = -1; NoCompression* = 0; BestSpeed* = 1;
  BestCompression* = 9;

  (* Formats *)
  ZlibFormat* = 0;  (* RFC 1950: a 2-byte header, deflate, Adler-32; PDF's /FlateDecode *)
  GzipFormat* = 1;  (* RFC 1952: gzip's header, deflate, CRC-32 and length *)
  RawFormat* = 2;   (* RFC 1951: deflate alone *)
  AnyFormat* = 3;   (* Inflater and Uncompress only: zlib or gzip, whichever it is *)

  (* Strategies, for NewDeflaterWith *)
  DefaultStrategy* = 0; Filtered* = 1; HuffmanOnly* = 2; Rle* = 3;
  Fixed* = 4;

  (* Error codes *)
  DataError* = 1;        (* the compressed data is corrupt, or not in the format asked for *)
  NeedDictionary* = 2;   (* the data was compressed with a preset dictionary *)
  Truncated* = 3;        (* the input ended before the compressed stream did *)
  DictionaryError* = 4;  (* SetDictionary: not the dictionary the data was compressed with *)
  TrailingData* = 5;     (* Uncompress: bytes after the end of the compressed stream *)

  (* ASSERT codes for programmer errors, in poc's trap message *)
  AssertClosed* = 66;  (* the stream has been closed *)
  AssertRange* = 67;   (* an argument out of range, or a NIL sink *)
  AssertZlib* = 68;    (* zlib refused: out of memory, a mismatched library, or a bug here *)
  AssertOrder* = 69;   (* a call at the wrong point in the stream's life *)

  (* Where checksums start *)
  InitialAdler32* = 1; InitialCrc32* = 0;

  DefaultWindowBits = 15; DefaultMemLevel = 8;
  ChunkSize = 16384;  (* each stream's output buffer, zlib's suggested size *)

TYPE
  Bytes* = POINTER TO ARRAY OF CHAR;

  (* Where a stream puts what it makes. Extend SinkDesc and override
     Write. SinkDesc's own Write throws the bytes away, so a plain Sink
     measures: a Deflater's TotalOut says how many there were. *)
  Sink* = POINTER TO SinkDesc;
  SinkDesc* = RECORD END;

  (* A Sink that keeps everything: data[0 .. len-1]. data grows as
     needed, so it is usually longer than len. *)
  Buffer* = POINTER TO BufferDesc;
  BufferDesc* = RECORD (SinkDesc)
    data-: Bytes;
    len-: LONGINT
  END;

  Error* = POINTER TO ErrorDesc;
  ErrorDesc* = RECORD
    code-: INTEGER;              (* one of the error codes above *)
    message-: ARRAY 128 OF CHAR  (* zlib's message if it gave one, else ours *)
  END;

  Deflater* = POINTER TO DeflaterDesc;
  DeflaterDesc* = RECORD
    strm: ZlibThin.Stream;  (* 0 once closed *)
    sink: Sink;
    out: Bytes;
    started: BOOLEAN;   (* Write or Flush since init or Reset *)
    finished: BOOLEAN   (* Finish since init or Reset *)
  END;

  Inflater* = POINTER TO InflaterDesc;
  InflaterDesc* = RECORD
    strm: ZlibThin.Stream;
    sink: Sink;
    out: Bytes;
    ended: BOOLEAN;     (* the compressed stream's end has been read *)
    needDict: BOOLEAN;  (* Write stopped for a dictionary *)
    failed: Error;      (* the error that stopped the stream, or NIL *)
    unused-: LONGINT    (* see Write *)
  END;

VAR openStreams: LONGINT;

(* ---- Sinks ---- *)

(* Receives buf[0 .. n-1]. buf is the stream's own buffer, which it
   reuses: copy what is to be kept. *)
PROCEDURE (s: Sink) Write*(VAR buf: ARRAY OF CHAR; n: LONGINT);
END Write;

PROCEDURE NewBuffer*(): Buffer;
  VAR b: Buffer;
BEGIN NEW(b); NEW(b.data, 256); b.len := 0; RETURN b
END NewBuffer;

PROCEDURE (b: Buffer) Write*(VAR buf: ARRAY OF CHAR; n: LONGINT);
  VAR bigger: Bytes; size: LONGINT;
BEGIN
  IF b.len + n > LEN(b.data^) THEN
    size := LEN(b.data^);
    REPEAT size := size * 2 UNTIL size >= b.len + n;
    NEW(bigger, size);
    SYSTEM.MOVE(SYSTEM.ADR(b.data[0]), SYSTEM.ADR(bigger[0]), SYSTEM.VAL(SYSTEM.ADDRESS, b.len));
    b.data := bigger
  END;
  IF n > 0 THEN
    SYSTEM.MOVE(SYSTEM.ADR(buf[0]), SYSTEM.ADR(b.data[b.len]), SYSTEM.VAL(SYSTEM.ADDRESS, n));
    INC(b.len, n)
  END
END Write;

(* Empties the buffer, keeping its memory. *)
PROCEDURE (b: Buffer) Clear*;
BEGIN b.len := 0
END Clear;

(* ---- Common ---- *)

(* poc keeps SYSTEM.INT64, ZlibThin's type for counts, apart from
   LONGINT, though under -OC, the only size model here, they are the
   same 64 bits. *)
PROCEDURE Long(x: SYSTEM.INT64): LONGINT;
BEGIN RETURN SYSTEM.VAL(LONGINT, x)
END Long;

PROCEDURE CheckRange(len, pos, n: LONGINT);
BEGIN ASSERT((pos >= 0) & (n >= 0) & (pos <= len - n), AssertRange)
END CheckRange;

(* At most ZlibThin.MaxAvail of n. *)
PROCEDURE Piece(n: LONGINT): LONGINT;
BEGIN
  IF n > ZlibThin.MaxAvail THEN RETURN ZlibThin.MaxAvail ELSE RETURN n END
END Piece;

PROCEDURE WindowBits(format, bits: INTEGER): INTEGER;
BEGIN
  CASE format OF
  | ZlibFormat: RETURN bits
  | GzipFormat: RETURN bits + 16
  | RawFormat: RETURN -bits
  | AnyFormat: RETURN bits + 32
  END
END WindowBits;

(* Copies the C string at p into s, cut to fit. *)
PROCEDURE CopyCString(p: SYSTEM.ADDRESS; VAR s: ARRAY OF CHAR);
  VAR i: LONGINT; c: CHAR;
BEGIN
  i := 0;
  IF p # 0 THEN
    SYSTEM.GET(p, c);
    WHILE (c # 0X) & (i < LEN(s) - 1) DO
      s[i] := c; INC(i); SYSTEM.GET(p + SYSTEM.VAL(SYSTEM.ADDRESS, i), c)
    END
  END;
  s[i] := 0X
END CopyCString;

PROCEDURE NewError(code: INTEGER; strm: ZlibThin.Stream; default: ARRAY OF CHAR): Error;
  VAR e: Error; p: SYSTEM.ADDRESS;
BEGIN
  NEW(e); e.code := code;
  p := 0; IF strm # 0 THEN p := ZlibThin.Msg(strm) END;
  IF p # 0 THEN CopyCString(p, e.message) ELSE COPY(default, e.message) END;
  RETURN e
END NewError;

(* How many streams are open: made and not yet closed, by Close or by
   the finalizer. For tests. *)
PROCEDURE OpenStreams*(): LONGINT;
BEGIN RETURN openStreams
END OpenStreams;

(* ---- Deflater ---- *)

PROCEDURE CloseDeflater(d: Deflater);
  VAR ret: SYSTEM.INT32;
BEGIN
  IF d.strm # 0 THEN
    (* deflateEnd says Z_DATA_ERROR when the stream was not finished,
       which only means pending output was discarded. *)
    ret := ZlibThin.DeflateEnd(d.strm);
    ZlibThin.StreamFree(d.strm);
    d.strm := 0; d.out := NIL; d.sink := NIL;
    DEC(openStreams)
  END
END CloseDeflater;

PROCEDURE FinalizeDeflater(obj: SYSTEM.PTR);
BEGIN CloseDeflater(SYSTEM.VAL(Deflater, obj))
END FinalizeDeflater;

(* A Deflater giving its output to sink, with every setting zlib
   offers. level: 0 to 9 or DefaultCompression. format: ZlibFormat,
   GzipFormat or RawFormat. windowBits: 9 to 15, the log of the
   window's size. memLevel: 1 to 9, how much memory zlib uses for its
   state, 8 by default. strategy: one of the strategy constants. *)
PROCEDURE NewDeflaterWith*(sink: Sink; level, format, windowBits, memLevel, strategy: INTEGER): Deflater;
  VAR d: Deflater; ret: SYSTEM.INT32;
BEGIN
  ASSERT(sink # NIL, AssertRange);
  ASSERT((level >= DefaultCompression) & (level <= BestCompression), AssertRange);
  ASSERT((format >= ZlibFormat) & (format <= RawFormat), AssertRange);
  ASSERT((windowBits >= 9) & (windowBits <= ZlibThin.MaxWBits), AssertRange);
  ASSERT((memLevel >= 1) & (memLevel <= ZlibThin.MaxMemLevel), AssertRange);
  ASSERT((strategy >= DefaultStrategy) & (strategy <= Fixed), AssertRange);
  NEW(d); d.sink := sink; NEW(d.out, ChunkSize);
  d.started := FALSE; d.finished := FALSE;
  d.strm := ZlibThin.StreamNew();
  ASSERT(d.strm # 0, AssertZlib);
  ret := ZlibThin.DeflateInit(d.strm, level, WindowBits(format, windowBits), memLevel, strategy);
  IF ret # ZlibThin.Ok THEN ZlibThin.StreamFree(d.strm); d.strm := 0 END;
  ASSERT(ret = ZlibThin.Ok, AssertZlib);
  INC(openStreams);
  GarbageCollectedHeap.RegisterFinalizer(d, FinalizeDeflater);
  RETURN d
END NewDeflaterWith;

(* A Deflater with zlib's usual window, memory and strategy. *)
PROCEDURE NewDeflater*(sink: Sink; level, format: INTEGER): Deflater;
BEGIN
  RETURN NewDeflaterWith(sink, level, format, DefaultWindowBits, DefaultMemLevel, DefaultStrategy)
END NewDeflater;

(* Runs deflate with flush over whatever input is set, giving every
   full or partial buffer to the sink, until zlib has room left over:
   then all the input is taken, and for SyncFlush and Finish all the
   output is out (zlib's own example, zpipe.c, does the same). *)
PROCEDURE Deflate(d: Deflater; flush: SYSTEM.INT32);
  VAR ret: SYSTEM.INT32; have: LONGINT;
BEGIN
  REPEAT
    ZlibThin.SetOutput(d.strm, SYSTEM.ADR(d.out[0]), LEN(d.out^));
    ret := ZlibThin.Deflate(d.strm, flush);
    (* BufError means no progress was possible, which is not an error:
       a flush with nothing new to flush gives it. *)
    ASSERT((ret = ZlibThin.Ok) OR (ret = ZlibThin.StreamEnd) OR (ret = ZlibThin.BufError), AssertZlib);
    have := LEN(d.out^) - Long(ZlibThin.AvailOut(d.strm));
    IF have > 0 THEN d.sink.Write(d.out^, have) END
  UNTIL Long(ZlibThin.AvailOut(d.strm)) # 0;
  ASSERT((flush # ZlibThin.Finish) OR (ret = ZlibThin.StreamEnd), AssertZlib);
  (* Leave no pointer into the caller's array, for the next call to
     find. *)
  ZlibThin.SetInput(d.strm, 0, 0)
END Deflate;

(* Compresses data[pos .. pos+n-1]. zlib holds back what it has not
   yet decided how to code, so the sink may get nothing until a later
   Write, Flush or Finish. *)
PROCEDURE (d: Deflater) Write*(VAR data: ARRAY OF CHAR; pos, n: LONGINT);
  VAR k: LONGINT;
BEGIN
  ASSERT(d.strm # 0, AssertClosed);
  ASSERT(~d.finished, AssertOrder);
  CheckRange(LEN(data), pos, n);
  d.started := TRUE;
  WHILE n > 0 DO
    k := Piece(n);
    ZlibThin.SetInput(d.strm, SYSTEM.ADR(data[pos]), k);
    Deflate(d, ZlibThin.NoFlush);
    INC(pos, k); DEC(n, k)
  END
END Write;

(* Pushes out everything written so far, ending on a byte boundary, so
   that what the sink has can be decompressed up to here (zlib's
   Z_SYNC_FLUSH). Each flush costs a few bytes and some compression. *)
PROCEDURE (d: Deflater) Flush*;
BEGIN
  ASSERT(d.strm # 0, AssertClosed);
  ASSERT(~d.finished, AssertOrder);
  d.started := TRUE;
  Deflate(d, ZlibThin.SyncFlush)
END Flush;

(* Ends the compressed stream: the sink gets the rest, with the
   format's trailer. Nothing more can be written until Reset. *)
PROCEDURE (d: Deflater) Finish*;
BEGIN
  ASSERT(d.strm # 0, AssertClosed);
  ASSERT(~d.finished, AssertOrder);
  Deflate(d, ZlibThin.Finish);
  d.finished := TRUE
END Finish;

(* Starts a new compressed stream with the same settings, giving its
   output to sink (which may be the old one). What was not finished
   is dropped. *)
PROCEDURE (d: Deflater) Reset*(sink: Sink);
  VAR ret: SYSTEM.INT32;
BEGIN
  ASSERT(d.strm # 0, AssertClosed);
  ASSERT(sink # NIL, AssertRange);
  ret := ZlibThin.DeflateReset(d.strm);
  ASSERT(ret = ZlibThin.Ok, AssertZlib);
  d.sink := sink; d.started := FALSE; d.finished := FALSE
END Reset;

(* Compresses with dict[pos .. pos+n-1] as a preset dictionary, bytes
   the data is likely to repeat. Only before the first Write or Flush
   after init or Reset; not for GzipFormat, which has no place to say
   so. The Inflater needs the same dictionary. *)
PROCEDURE (d: Deflater) SetDictionary*(VAR dict: ARRAY OF CHAR; pos, n: LONGINT);
  VAR ret: SYSTEM.INT32; p: SYSTEM.ADDRESS;
BEGIN
  ASSERT(d.strm # 0, AssertClosed);
  ASSERT(~d.started & ~d.finished, AssertOrder);
  CheckRange(LEN(dict), pos, n);
  ASSERT(n <= ZlibThin.MaxAvail, AssertRange);
  p := 0; IF n > 0 THEN p := SYSTEM.ADR(dict[pos]) END;
  ret := ZlibThin.DeflateSetDictionary(d.strm, p, SHORT(n));
  (* StreamError here means a gzip stream, which can't take one. *)
  ASSERT(ret # ZlibThin.StreamError, AssertOrder);
  ASSERT(ret = ZlibThin.Ok, AssertZlib)
END SetDictionary;

(* The most bytes Finish can give for n bytes written to a new stream
   in one Write, with this Deflater's settings. *)
PROCEDURE (d: Deflater) Bound*(n: LONGINT): LONGINT;
BEGIN
  ASSERT(d.strm # 0, AssertClosed);
  ASSERT(n >= 0, AssertRange);
  RETURN Long(ZlibThin.DeflateBound(d.strm, n))
END Bound;

(* Bytes written and bytes given to the sink since init or Reset.
   Where C's long has 32 bits (i386), they wrap at 4 GB. *)
PROCEDURE (d: Deflater) TotalIn*(): LONGINT;
BEGIN ASSERT(d.strm # 0, AssertClosed); RETURN Long(ZlibThin.TotalIn(d.strm))
END TotalIn;

PROCEDURE (d: Deflater) TotalOut*(): LONGINT;
BEGIN ASSERT(d.strm # 0, AssertClosed); RETURN Long(ZlibThin.TotalOut(d.strm))
END TotalOut;

(* Frees zlib's state. Idempotent. Output not yet finished is lost. *)
PROCEDURE (d: Deflater) Close*;
BEGIN CloseDeflater(d)
END Close;

PROCEDURE (d: Deflater) Closed*(): BOOLEAN;
BEGIN RETURN d.strm = 0
END Closed;

(* ---- Inflater ---- *)

PROCEDURE CloseInflater(i: Inflater);
  VAR ret: SYSTEM.INT32;
BEGIN
  IF i.strm # 0 THEN
    ret := ZlibThin.InflateEnd(i.strm);
    ZlibThin.StreamFree(i.strm);
    i.strm := 0; i.out := NIL; i.sink := NIL;
    DEC(openStreams)
  END
END CloseInflater;

PROCEDURE FinalizeInflater(obj: SYSTEM.PTR);
BEGIN CloseInflater(SYSTEM.VAL(Inflater, obj))
END FinalizeInflater;

(* An Inflater giving its output to sink. format: any of the four;
   AnyFormat takes zlib or gzip, whichever the data turns out to be.
   It accepts a window of any size up to 15 bits. *)
PROCEDURE NewInflater*(sink: Sink; format: INTEGER): Inflater;
  VAR i: Inflater; ret: SYSTEM.INT32;
BEGIN
  ASSERT(sink # NIL, AssertRange);
  ASSERT((format >= ZlibFormat) & (format <= AnyFormat), AssertRange);
  NEW(i); i.sink := sink; NEW(i.out, ChunkSize);
  i.ended := FALSE; i.needDict := FALSE; i.failed := NIL; i.unused := 0;
  i.strm := ZlibThin.StreamNew();
  ASSERT(i.strm # 0, AssertZlib);
  ret := ZlibThin.InflateInit(i.strm, WindowBits(format, DefaultWindowBits));
  IF ret # ZlibThin.Ok THEN ZlibThin.StreamFree(i.strm); i.strm := 0 END;
  ASSERT(ret = ZlibThin.Ok, AssertZlib);
  INC(openStreams);
  GarbageCollectedHeap.RegisterFinalizer(i, FinalizeInflater);
  RETURN i
END NewInflater;

(* Decompresses data[pos .. pos+n-1], giving the sink what it makes.

   Returns FALSE, with err, if the data is corrupt (DataError), after
   which the stream is spent: every later Write and Finish gives the
   same error until Reset. Returns FALSE with NeedDictionary if the
   data asks for a preset dictionary: then call SetDictionary, and
   Write the unused bytes again, the last unused of this call's.

   Reading the compressed stream's end sets Ended, and unused to the
   number of this call's bytes after the end -- the last unused of
   them -- which belong to whatever follows (a second gzip member, the
   rest of a file). Write after the end halts (AssertOrder): check
   Ended. *)
PROCEDURE (i: Inflater) Write*(VAR data: ARRAY OF CHAR; pos, n: LONGINT; VAR err: Error): BOOLEAN;
  VAR k, have: LONGINT; ret: SYSTEM.INT32;
BEGIN
  ASSERT(i.strm # 0, AssertClosed);
  ASSERT(~i.ended, AssertOrder);
  CheckRange(LEN(data), pos, n);
  err := i.failed; i.unused := 0;
  IF i.needDict THEN err := NewError(NeedDictionary, 0, "a preset dictionary is needed") END;
  WHILE (err = NIL) & (n > 0) DO
    k := Piece(n);
    ZlibThin.SetInput(i.strm, SYSTEM.ADR(data[pos]), k);
    REPEAT
      ZlibThin.SetOutput(i.strm, SYSTEM.ADR(i.out[0]), LEN(i.out^));
      ret := ZlibThin.Inflate(i.strm, ZlibThin.NoFlush);
      ASSERT((ret # ZlibThin.StreamError) & (ret # ZlibThin.MemError), AssertZlib);
      have := LEN(i.out^) - Long(ZlibThin.AvailOut(i.strm));
      IF have > 0 THEN i.sink.Write(i.out^, have) END
    UNTIL (Long(ZlibThin.AvailOut(i.strm)) # 0) OR (ret = ZlibThin.StreamEnd)
       OR (ret = ZlibThin.NeedDict) OR (ret = ZlibThin.DataError);
    (* Inflate stops only when it runs out of input or of room, so
       with room left and no other reason, all k bytes were taken. *)
    IF ret = ZlibThin.DataError THEN
      i.failed := NewError(DataError, i.strm, "invalid compressed data"); err := i.failed
    ELSIF ret = ZlibThin.NeedDict THEN
      i.needDict := TRUE;
      i.unused := Long(ZlibThin.AvailIn(i.strm)) + n - k;
      err := NewError(NeedDictionary, 0, "a preset dictionary is needed")
    ELSIF ret = ZlibThin.StreamEnd THEN
      i.ended := TRUE;
      i.unused := Long(ZlibThin.AvailIn(i.strm)) + n - k;
      n := 0
    ELSE
      INC(pos, k); DEC(n, k)
    END
  END;
  ZlibThin.SetInput(i.strm, 0, 0);
  RETURN err = NIL
END Write;

(* Gives the dictionary asked for when Write returned NeedDictionary.
   FALSE, with DictionaryError, if it is not the one the data was
   compressed with. *)
PROCEDURE (i: Inflater) SetDictionary*(VAR dict: ARRAY OF CHAR; pos, n: LONGINT; VAR err: Error): BOOLEAN;
  VAR ret: SYSTEM.INT32; p: SYSTEM.ADDRESS;
BEGIN
  ASSERT(i.strm # 0, AssertClosed);
  ASSERT(i.needDict, AssertOrder);
  CheckRange(LEN(dict), pos, n);
  ASSERT(n <= ZlibThin.MaxAvail, AssertRange);
  p := 0; IF n > 0 THEN p := SYSTEM.ADR(dict[pos]) END;
  ret := ZlibThin.InflateSetDictionary(i.strm, p, SHORT(n));
  ASSERT((ret = ZlibThin.Ok) OR (ret = ZlibThin.DataError), AssertZlib);
  IF ret = ZlibThin.Ok THEN
    i.needDict := FALSE; err := NIL
  ELSE
    err := NewError(DictionaryError, 0, "not the dictionary the data was compressed with")
  END;
  RETURN err = NIL
END SetDictionary;

(* Says the input is over: TRUE if the compressed stream's end was
   read, FALSE with an error if not (Truncated, or the error that
   stopped the stream). The Inflater stays open, for Reset. *)
PROCEDURE (i: Inflater) Finish*(VAR err: Error): BOOLEAN;
BEGIN
  ASSERT(i.strm # 0, AssertClosed);
  err := i.failed;
  IF (err = NIL) & ~i.ended THEN
    err := NewError(Truncated, 0, "the compressed data ends early")
  END;
  RETURN err = NIL
END Finish;

(* TRUE once the compressed stream's end has been read. *)
PROCEDURE (i: Inflater) Ended*(): BOOLEAN;
BEGIN ASSERT(i.strm # 0, AssertClosed); RETURN i.ended
END Ended;

(* Starts on a new compressed stream in the same format, giving its
   output to sink. *)
PROCEDURE (i: Inflater) Reset*(sink: Sink);
  VAR ret: SYSTEM.INT32;
BEGIN
  ASSERT(i.strm # 0, AssertClosed);
  ASSERT(sink # NIL, AssertRange);
  ret := ZlibThin.InflateReset(i.strm);
  ASSERT(ret = ZlibThin.Ok, AssertZlib);
  i.sink := sink; i.ended := FALSE; i.needDict := FALSE; i.failed := NIL; i.unused := 0
END Reset;

PROCEDURE (i: Inflater) TotalIn*(): LONGINT;
BEGIN ASSERT(i.strm # 0, AssertClosed); RETURN Long(ZlibThin.TotalIn(i.strm))
END TotalIn;

PROCEDURE (i: Inflater) TotalOut*(): LONGINT;
BEGIN ASSERT(i.strm # 0, AssertClosed); RETURN Long(ZlibThin.TotalOut(i.strm))
END TotalOut;

PROCEDURE (i: Inflater) Close*;
BEGIN CloseInflater(i)
END Close;

PROCEDURE (i: Inflater) Closed*(): BOOLEAN;
BEGIN RETURN i.strm = 0
END Closed;

(* ---- In one call ---- *)

(* data[pos .. pos+n-1] compressed, in a new Buffer. *)
PROCEDURE Compress*(VAR data: ARRAY OF CHAR; pos, n: LONGINT; level, format: INTEGER): Buffer;
  VAR b: Buffer; d: Deflater;
BEGIN
  CheckRange(LEN(data), pos, n);
  b := NewBuffer();
  d := NewDeflater(b, level, format);
  d.Write(data, pos, n); d.Finish; d.Close;
  RETURN b
END Compress;

(* Decompresses data[pos .. pos+n-1], which must be exactly one
   compressed stream, into a new Buffer out. FALSE, with err and out
   NIL, if it is corrupt, ends early, is followed by other bytes
   (TrailingData), or needs a dictionary. *)
PROCEDURE Uncompress*(VAR data: ARRAY OF CHAR; pos, n: LONGINT; format: INTEGER;
                      VAR out: Buffer; VAR err: Error): BOOLEAN;
  VAR i: Inflater; ok: BOOLEAN;
BEGIN
  CheckRange(LEN(data), pos, n);
  out := NewBuffer();
  i := NewInflater(out, format);
  ok := i.Write(data, pos, n, err);
  IF ok THEN ok := i.Finish(err) END;
  IF ok & (i.unused > 0) THEN
    err := NewError(TrailingData, 0, "bytes follow the compressed data"); ok := FALSE
  END;
  i.Close;
  IF ~ok THEN out := NIL END;
  RETURN ok
END Uncompress;

(* ---- Checksums ---- *)

(* The Adler-32 checksum adler carried on over data[pos .. pos+n-1].
   Start with InitialAdler32. *)
PROCEDURE Adler32*(adler: LONGINT; VAR data: ARRAY OF CHAR; pos, n: LONGINT): LONGINT;
  VAR k: LONGINT;
BEGIN
  CheckRange(LEN(data), pos, n);
  WHILE n > 0 DO
    k := Piece(n);
    adler := Long(ZlibThin.Adler32(adler, SYSTEM.ADR(data[pos]), SYSTEM.VAL(SYSTEM.ADDRESS, k)));
    INC(pos, k); DEC(n, k)
  END;
  RETURN adler
END Adler32;

(* The CRC-32 (ISO 3309, as gzip and PNG use) crc carried on over
   data[pos .. pos+n-1]. Start with InitialCrc32. *)
PROCEDURE Crc32*(crc: LONGINT; VAR data: ARRAY OF CHAR; pos, n: LONGINT): LONGINT;
  VAR k: LONGINT;
BEGIN
  CheckRange(LEN(data), pos, n);
  WHILE n > 0 DO
    k := Piece(n);
    crc := Long(ZlibThin.Crc32(crc, SYSTEM.ADR(data[pos]), SYSTEM.VAL(SYSTEM.ADDRESS, k)));
    INC(pos, k); DEC(n, k)
  END;
  RETURN crc
END Crc32;

(* ---- The library ---- *)

(* The linked library's version, such as "1.3.2", or "1.3.1.zlib-ng"
   for zlib-ng's compatible library. *)
PROCEDURE Version*(VAR s: ARRAY OF CHAR);
BEGIN CopyCString(ZlibThin.ZlibVersion(), s)
END Version;

BEGIN openStreams := 0
END Zlib.
