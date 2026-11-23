MODULE HaltClosed; (* Write to a closed Deflater: AssertClosed (66) *)
IMPORT Zlib;
VAR d: Zlib.Deflater; s: Zlib.Sink; a: ARRAY 4 OF CHAR;
BEGIN
  NEW(s); a := "abc";
  d := Zlib.NewDeflater(s, Zlib.DefaultCompression, Zlib.ZlibFormat);
  d.Close; d.Write(a, 0, 3)
END HaltClosed.
