MODULE ZlibThin; (* Thin zlib binding: direct calls, no ownership or error policy *)

(* Copyright (c) 2026, T. Kurt Bond. BSD 3-Clause License; see LICENSE.

   Low-level access to zlib's standard API (<zlib.h>, linked with -lz):
   zlib itself, or zlib-ng's compatible library, whichever the host has.
   A Stream is a SYSTEM.ADDRESS holding a z_stream pointer, which
   ZlibThin.c allocates; buffers go in as an address plus a count.
   Nothing here copies, frees or checks: build on Zlib, not on this
   module.

   Two kinds of declaration. A zlib function that takes and returns
   only pointers and ints is declared here as an external ["C"]
   procedure and wrapped in an exported Oberon one, so the interface
   is Oberon procedures throughout. What an Oberon declaration cannot
   say is in ZlibThin.c beside this file, which poc compiles with clang
   against the installed <zlib.h>: z_stream's fields, the init macros,
   and the functions that carry a uLong, whose width is the host's
   long.

   Types: boundary signatures use explicit sizes -- SYSTEM.INT32 for C
   int, SYSTEM.INT64 for a count or a uLong, SYSTEM.ADDRESS for a
   pointer or a size_t -- so each says what C type it carries, and
   means the same under -OC and -O2. *)

IMPORT SYSTEM;

CONST
  (* zlib's return codes, flush values, levels and strategies. zlib.h
     documents them as fixed numbers, and TestThin checks each against
     the installed header (ZlibThin.c's constant), in this order. *)
  Ok* = 0; StreamEnd* = 1; NeedDict* = 2; Errno* = -1; StreamError* = -2;
  DataError* = -3; MemError* = -4; BufError* = -5; VersionError* = -6;

  NoFlush* = 0; PartialFlush* = 1; SyncFlush* = 2; FullFlush* = 3;
  Finish* = 4; Block* = 5;

  NoCompression* = 0; BestSpeed* = 1; BestCompression* = 9;
  DefaultCompression* = -1;

  Filtered* = 1; HuffmanOnly* = 2; Rle* = 3; Fixed* = 4;
  DefaultStrategy* = 0;

  MaxWBits* = 15; MaxMemLevel* = 9;

  Constants* = 26;  (* how many constants TestConstant checks *)

  (* The most bytes handed to zlib at once. avail_in and avail_out are
     uInt, 32 bits on every host poc targets; 1 GB stays well inside,
     and Zlib cuts longer buffers into pieces this size. *)
  MaxAvail* = 40000000H;

TYPE
  Stream* = SYSTEM.ADDRESS;  (* z_stream* *)

(* ---- ZlibThin.c ---- *)

PROCEDURE ["C", "ZlibThin.-stream-new"] CStreamNew(): Stream;
PROCEDURE ["C", "ZlibThin.-stream-free"] CStreamFree(s: Stream);
PROCEDURE ["C", "ZlibThin.-deflate-init"] CDeflateInit(s: Stream; level, windowBits, memLevel, strategy: SYSTEM.INT32): SYSTEM.INT32;
PROCEDURE ["C", "ZlibThin.-inflate-init"] CInflateInit(s: Stream; windowBits: SYSTEM.INT32): SYSTEM.INT32;
PROCEDURE ["C", "ZlibThin.-set-input"] CSetInput(s: Stream; next: SYSTEM.ADDRESS; avail: SYSTEM.INT64);
PROCEDURE ["C", "ZlibThin.-set-output"] CSetOutput(s: Stream; next: SYSTEM.ADDRESS; avail: SYSTEM.INT64);
PROCEDURE ["C", "ZlibThin.-avail-in"] CAvailIn(s: Stream): SYSTEM.INT64;
PROCEDURE ["C", "ZlibThin.-avail-out"] CAvailOut(s: Stream): SYSTEM.INT64;
PROCEDURE ["C", "ZlibThin.-total-in"] CTotalIn(s: Stream): SYSTEM.INT64;
PROCEDURE ["C", "ZlibThin.-total-out"] CTotalOut(s: Stream): SYSTEM.INT64;
PROCEDURE ["C", "ZlibThin.-msg"] CMsg(s: Stream): SYSTEM.ADDRESS;
PROCEDURE ["C", "ZlibThin.-deflate-bound"] CDeflateBound(s: Stream; sourceLen: SYSTEM.INT64): SYSTEM.INT64;
PROCEDURE ["C", "ZlibThin.-adler32"] CAdler32(adler: SYSTEM.INT64; buf, len: SYSTEM.ADDRESS): SYSTEM.INT64;
PROCEDURE ["C", "ZlibThin.-crc32"] CCrc32(crc: SYSTEM.INT64; buf, len: SYSTEM.ADDRESS): SYSTEM.INT64;
PROCEDURE ["C", "ZlibThin.-constant"] CConstant(which: SYSTEM.INT32): SYSTEM.INT32;
PROCEDURE ["C", "ZlibThin.-uint-max"] CUIntMax(): SYSTEM.INT64;

(* ---- zlib, called directly ---- *)

PROCEDURE ["C", "deflate"] CDeflate(s: Stream; flush: SYSTEM.INT32): SYSTEM.INT32;
PROCEDURE ["C", "deflateEnd"] CDeflateEnd(s: Stream): SYSTEM.INT32;
PROCEDURE ["C", "deflateReset"] CDeflateReset(s: Stream): SYSTEM.INT32;
PROCEDURE ["C", "deflateSetDictionary"] CDeflateSetDictionary(s: Stream; dict: SYSTEM.ADDRESS; len: SYSTEM.INT32): SYSTEM.INT32;
PROCEDURE ["C", "inflate"] CInflate(s: Stream; flush: SYSTEM.INT32): SYSTEM.INT32;
PROCEDURE ["C", "inflateEnd"] CInflateEnd(s: Stream): SYSTEM.INT32;
PROCEDURE ["C", "inflateReset"] CInflateReset(s: Stream): SYSTEM.INT32;
PROCEDURE ["C", "inflateSetDictionary"] CInflateSetDictionary(s: Stream; dict: SYSTEM.ADDRESS; len: SYSTEM.INT32): SYSTEM.INT32;
PROCEDURE ["C", "zlibVersion"] CZlibVersion(): SYSTEM.ADDRESS;

(* ---- Streams ---- *)

(* A new zeroed z_stream, ready for DeflateInit or InflateInit; 0 if
   there is no memory. Free it with StreamFree after DeflateEnd or
   InflateEnd. *)
PROCEDURE StreamNew*(): Stream;
BEGIN RETURN CStreamNew()
END StreamNew;

PROCEDURE StreamFree*(s: Stream);
BEGIN CStreamFree(s)
END StreamFree;

(* deflateInit2 with method Z_DEFLATED. windowBits 9 to 15 makes the
   zlib format, 25 to 31 (16 more) gzip, and -9 to -15 raw deflate. *)
PROCEDURE DeflateInit*(s: Stream; level, windowBits, memLevel, strategy: SYSTEM.INT32): SYSTEM.INT32;
BEGIN RETURN CDeflateInit(s, level, windowBits, memLevel, strategy)
END DeflateInit;

(* inflateInit2. windowBits as DeflateInit's, or 32 more (40 to 47)
   to read either the zlib or the gzip format, whichever it finds. *)
PROCEDURE InflateInit*(s: Stream; windowBits: SYSTEM.INT32): SYSTEM.INT32;
BEGIN RETURN CInflateInit(s, windowBits)
END InflateInit;

(* The next avail bytes zlib reads, at next. zlib keeps next across
   calls but reads it only during Deflate and Inflate, so the memory
   need live only until the next call that sets it again. avail must
   not exceed MaxAvail. *)
PROCEDURE SetInput*(s: Stream; next: SYSTEM.ADDRESS; avail: SYSTEM.INT64);
BEGIN CSetInput(s, next, avail)
END SetInput;

(* Where zlib writes, at most avail bytes: as SetInput. *)
PROCEDURE SetOutput*(s: Stream; next: SYSTEM.ADDRESS; avail: SYSTEM.INT64);
BEGIN CSetOutput(s, next, avail)
END SetOutput;

PROCEDURE AvailIn*(s: Stream): SYSTEM.INT64;
BEGIN RETURN CAvailIn(s)
END AvailIn;

PROCEDURE AvailOut*(s: Stream): SYSTEM.INT64;
BEGIN RETURN CAvailOut(s)
END AvailOut;

(* Bytes read and written since the last init or reset. They are
   uLong in zlib, so they wrap at 4 GB where C's long has 32 bits. *)
PROCEDURE TotalIn*(s: Stream): SYSTEM.INT64;
BEGIN RETURN CTotalIn(s)
END TotalIn;

PROCEDURE TotalOut*(s: Stream): SYSTEM.INT64;
BEGIN RETURN CTotalOut(s)
END TotalOut;

(* The address of zlib's 0X-terminated message for the last error, or
   0. The string is zlib's own and static: copy it, never free it. *)
PROCEDURE Msg*(s: Stream): SYSTEM.ADDRESS;
BEGIN RETURN CMsg(s)
END Msg;

PROCEDURE Deflate*(s: Stream; flush: SYSTEM.INT32): SYSTEM.INT32;
BEGIN RETURN CDeflate(s, flush)
END Deflate;

PROCEDURE DeflateEnd*(s: Stream): SYSTEM.INT32;
BEGIN RETURN CDeflateEnd(s)
END DeflateEnd;

PROCEDURE DeflateReset*(s: Stream): SYSTEM.INT32;
BEGIN RETURN CDeflateReset(s)
END DeflateReset;

(* Only before the first Deflate after init or reset. zlib copies the
   dictionary. *)
PROCEDURE DeflateSetDictionary*(s: Stream; dict: SYSTEM.ADDRESS; len: SYSTEM.INT32): SYSTEM.INT32;
BEGIN RETURN CDeflateSetDictionary(s, dict, len)
END DeflateSetDictionary;

(* An upper bound on the compressed size of sourceLen bytes, for this
   stream's settings, when all of it goes in one Deflate with Finish. *)
PROCEDURE DeflateBound*(s: Stream; sourceLen: SYSTEM.INT64): SYSTEM.INT64;
BEGIN RETURN CDeflateBound(s, sourceLen)
END DeflateBound;

PROCEDURE Inflate*(s: Stream; flush: SYSTEM.INT32): SYSTEM.INT32;
BEGIN RETURN CInflate(s, flush)
END Inflate;

PROCEDURE InflateEnd*(s: Stream): SYSTEM.INT32;
BEGIN RETURN CInflateEnd(s)
END InflateEnd;

PROCEDURE InflateReset*(s: Stream): SYSTEM.INT32;
BEGIN RETURN CInflateReset(s)
END InflateReset;

(* After Inflate returns NeedDict (zlib format), or at any time for a
   raw stream. zlib copies the dictionary. *)
PROCEDURE InflateSetDictionary*(s: Stream; dict: SYSTEM.ADDRESS; len: SYSTEM.INT32): SYSTEM.INT32;
BEGIN RETURN CInflateSetDictionary(s, dict, len)
END InflateSetDictionary;

(* ---- Checksums ---- *)

(* adler32_z and crc32_z: the checksum adler or crc carried on over
   len bytes at buf. Start Adler-32 with 1 and CRC-32 with 0. *)
PROCEDURE Adler32*(adler: SYSTEM.INT64; buf, len: SYSTEM.ADDRESS): SYSTEM.INT64;
BEGIN RETURN CAdler32(adler, buf, len)
END Adler32;

PROCEDURE Crc32*(crc: SYSTEM.INT64; buf, len: SYSTEM.ADDRESS): SYSTEM.INT64;
BEGIN RETURN CCrc32(crc, buf, len)
END Crc32;

(* ---- The library ---- *)

(* The address of the linked library's 0X-terminated version string,
   such as "1.3.1.zlib-ng" or "1.3.2". *)
PROCEDURE ZlibVersion*(): SYSTEM.ADDRESS;
BEGIN RETURN CZlibVersion()
END ZlibVersion;

(* For TestThin: zlib.h's value of the which'th constant above, in
   their order (Ok is 0, MaxMemLevel is Constants - 1). *)
PROCEDURE TestConstant*(which: SYSTEM.INT32): SYSTEM.INT32;
BEGIN RETURN CConstant(which)
END TestConstant;

(* For TestThin: UINT_MAX, which MaxAvail must not exceed. *)
PROCEDURE UIntMax*(): SYSTEM.INT64;
BEGIN RETURN CUIntMax()
END UIntMax;

END ZlibThin.
