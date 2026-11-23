MODULE HaltSlice; (* A slice past the array's end: AssertRange (67) *)
IMPORT Zlib;
VAR b: Zlib.Buffer; a: ARRAY 10 OF CHAR;
BEGIN
  b := Zlib.Compress(a, 5, 10, Zlib.DefaultCompression, Zlib.ZlibFormat)
END HaltSlice.
