MODULE TestChecksums; (* Adler-32 and CRC-32, whole and in pieces *)

IMPORT Zlib, Check, Hex;

PROCEDURE Known;
  VAR b: Zlib.Bytes; n: LONGINT;
BEGIN
  b := Hex.Text("Wikipedia", n);
  Check.Check(Zlib.Adler32(Zlib.InitialAdler32, b^, 0, n) = 11E60398H, "Adler-32 of Wikipedia is 11E60398");
  b := Hex.Text("123456789", n);
  Check.Check(Zlib.Crc32(Zlib.InitialCrc32, b^, 0, n) = 0CBF43926H, "CRC-32 of 123456789 is CBF43926");
  Check.Check(Zlib.Adler32(Zlib.InitialAdler32, b^, 0, 0) = 1, "Adler-32 of nothing is 1");
  Check.Check(Zlib.Crc32(Zlib.InitialCrc32, b^, 0, 0) = 0, "CRC-32 of nothing is 0");
  b := Hex.Lout(n);
  (* Python's zlib.adler32 and zlib.crc32 of the same text; the
     Adler-32 is also the zlib vector's trailer. *)
  Check.Check(Zlib.Adler32(Zlib.InitialAdler32, b^, 0, n) = 6CD529E9H, "Adler-32 of the test text");
  Check.Check(Zlib.Crc32(Zlib.InitialCrc32, b^, 0, n) = 7F139BC6H, "CRC-32 of the test text")
END Known;

(* Carried on piece by piece, the same as all at once. *)
PROCEDURE Pieces;
  VAR b: Zlib.Bytes; n, a, c, i: LONGINT;
BEGIN
  b := Hex.Sample(10000); n := 10000;
  a := Zlib.InitialAdler32; c := Zlib.InitialCrc32; i := 0;
  WHILE i < n DO
    a := Zlib.Adler32(a, b^, i, 7); c := Zlib.Crc32(c, b^, i, 7);
    INC(i, 7); IF n - i < 7 THEN a := Zlib.Adler32(a, b^, i, n - i); c := Zlib.Crc32(c, b^, i, n - i); i := n END
  END;
  Check.Check(a = Zlib.Adler32(Zlib.InitialAdler32, b^, 0, n), "Adler-32 in pieces");
  Check.Check(c = Zlib.Crc32(Zlib.InitialCrc32, b^, 0, n), "CRC-32 in pieces")
END Pieces;

PROCEDURE Version;
  VAR v: ARRAY 32 OF CHAR;
BEGIN
  Zlib.Version(v);
  Check.Check((v[0] = "1") & (v[1] = "."), "the version looks like 1.x")
END Version;

BEGIN
  Known; Pieces; Version;
  Check.Summary
END TestChecksums.
