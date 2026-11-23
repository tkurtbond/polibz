MODULE ExampleRoundTrip; (* Compress a text, decompress it, and check it *)

(* Prints nothing that depends on the library: zlib and zlib-ng make
   different compressed bytes from the same input, so the compressed
   size is checked, not printed. *)

IMPORT Out, Zlib;

VAR
  text: ARRAY 200 OF CHAR; n, i: LONGINT;
  packed, back: Zlib.Buffer; err: Zlib.Error; same: BOOLEAN;

BEGIN
  text := "Lout is a document formatting system. Lout is a document formatting system.";
  n := 0; WHILE text[n] # 0X DO INC(n) END;

  packed := Zlib.Compress(text, 0, n, Zlib.BestCompression, Zlib.ZlibFormat);
  Out.String("compressed "); Out.Int(n, 0); Out.String(" bytes: ");
  IF packed.len < n THEN Out.String("smaller") ELSE Out.String("not smaller") END; Out.Ln;

  IF Zlib.Uncompress(packed.data^, 0, packed.len, Zlib.ZlibFormat, back, err) THEN
    same := back.len = n; i := 0;
    WHILE same & (i < n) DO same := back.data[i] = text[i]; INC(i) END;
    Out.String("decompressed "); Out.Int(back.len, 0); Out.String(" bytes: ");
    IF same THEN Out.String("the same") ELSE Out.String("different") END; Out.Ln
  ELSE
    Out.String("error: "); Out.String(err.message); Out.Ln
  END;

  Out.String("Adler-32: "); Out.Hex(Zlib.Adler32(Zlib.InitialAdler32, text, 0, n), 8); Out.Ln;
  Out.String("CRC-32: "); Out.Hex(Zlib.Crc32(Zlib.InitialCrc32, text, 0, n), 8); Out.Ln
END ExampleRoundTrip.
