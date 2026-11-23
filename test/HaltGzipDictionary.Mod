MODULE HaltGzipDictionary; (* A dictionary for gzip, which has no place for one: AssertOrder (69) *)
IMPORT Zlib;
VAR d: Zlib.Deflater; s: Zlib.Sink; a: ARRAY 4 OF CHAR;
BEGIN
  NEW(s); a := "abc";
  d := Zlib.NewDeflater(s, Zlib.DefaultCompression, Zlib.GzipFormat);
  d.SetDictionary(a, 0, 3)
END HaltGzipDictionary.
