MODULE HaltDictionaryLate; (* SetDictionary after Write: AssertOrder (69) *)
IMPORT Zlib;
VAR d: Zlib.Deflater; s: Zlib.Sink; a: ARRAY 4 OF CHAR;
BEGIN
  NEW(s); a := "abc";
  d := Zlib.NewDeflater(s, Zlib.DefaultCompression, Zlib.ZlibFormat);
  d.Write(a, 0, 3); d.SetDictionary(a, 0, 3)
END HaltDictionaryLate.
