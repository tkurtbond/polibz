MODULE HaltLevel; (* Level 10: AssertRange (67) *)
IMPORT Zlib;
VAR d: Zlib.Deflater; s: Zlib.Sink;
BEGIN
  NEW(s); d := Zlib.NewDeflater(s, 10, Zlib.ZlibFormat)
END HaltLevel.
