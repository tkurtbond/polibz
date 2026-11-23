MODULE HaltInflaterClosed; (* Write to a closed Inflater: AssertClosed (66) *)
IMPORT Zlib;
VAR i: Zlib.Inflater; s: Zlib.Sink; a: ARRAY 4 OF CHAR; err: Zlib.Error; ok: BOOLEAN;
BEGIN
  NEW(s); a := "abc";
  i := Zlib.NewInflater(s, Zlib.ZlibFormat);
  i.Close; ok := i.Write(a, 0, 3, err)
END HaltInflaterClosed.
