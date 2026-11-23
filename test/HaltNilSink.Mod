MODULE HaltNilSink; (* A NIL sink: AssertRange (67) *)
IMPORT Zlib;
VAR d: Zlib.Deflater;
BEGIN
  d := Zlib.NewDeflater(NIL, Zlib.DefaultCompression, Zlib.ZlibFormat)
END HaltNilSink.
