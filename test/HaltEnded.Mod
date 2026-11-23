MODULE HaltEnded; (* Inflater.Write after the stream's end: AssertOrder (69) *)
IMPORT Zlib;
VAR b, out: Zlib.Buffer; i: Zlib.Inflater; a: ARRAY 4 OF CHAR; err: Zlib.Error; ok: BOOLEAN;
BEGIN
  a := "abc";
  b := Zlib.Compress(a, 0, 3, Zlib.DefaultCompression, Zlib.ZlibFormat);
  out := Zlib.NewBuffer(); i := Zlib.NewInflater(out, Zlib.ZlibFormat);
  ok := i.Write(b.data^, 0, b.len, err);
  ok := i.Write(b.data^, 0, b.len, err)
END HaltEnded.
