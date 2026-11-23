MODULE Hex; (* Test helpers: bytes from hexadecimal, texts, comparisons *)

IMPORT Zlib;

PROCEDURE Digit(c: CHAR): INTEGER;
BEGIN
  IF (c >= "0") & (c <= "9") THEN RETURN ORD(c) - ORD("0")
  ELSE RETURN ORD(c) - ORD("a") + 10
  END
END Digit;

(* The bytes written in hex (lowercase, no spaces) in s. *)
PROCEDURE Bytes*(s: ARRAY OF CHAR; VAR n: LONGINT): Zlib.Bytes;
  VAR b: Zlib.Bytes; i: LONGINT;
BEGIN
  n := 0; WHILE s[2 * n] # 0X DO INC(n) END;
  NEW(b, n + 1);
  FOR i := 0 TO n - 1 DO b[i] := CHR(Digit(s[2 * i]) * 16 + Digit(s[2 * i + 1])) END;
  RETURN b
END Bytes;

(* The 0X-terminated s as bytes, without its 0X. *)
PROCEDURE Text*(s: ARRAY OF CHAR; VAR n: LONGINT): Zlib.Bytes;
  VAR b: Zlib.Bytes; i: LONGINT;
BEGIN
  n := 0; WHILE s[n] # 0X DO INC(n) END;
  NEW(b, n + 1);
  FOR i := 0 TO n - 1 DO b[i] := s[i] END;
  RETURN b
END Text;

(* The test text the vectors were made from: three times the line. *)
PROCEDURE Lout*(VAR n: LONGINT): Zlib.Bytes;
  VAR line, b: Zlib.Bytes; m, i, j: LONGINT;
BEGIN
  line := Text("Lout is a document formatting system.", m);
  line[m] := 0AX; INC(m);  (* Text leaves room for its 0X *)
  n := 3 * m; NEW(b, n);
  FOR i := 0 TO 2 DO FOR j := 0 TO m - 1 DO b[i * m + j] := line[j] END END;
  RETURN b
END Lout;

(* TRUE if b holds exactly the n bytes of want. *)
PROCEDURE Same*(b: Zlib.Buffer; VAR want: ARRAY OF CHAR; n: LONGINT): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  IF (b = NIL) OR (b.len # n) THEN RETURN FALSE END;
  i := 0; WHILE (i < n) & (b.data[i] = want[i]) DO INC(i) END;
  RETURN i = n
END Same;

(* n bytes that compress, but not to nothing: a pseudo-random walk
   over a small alphabet (a linear congruential generator, so the same
   every run). *)
PROCEDURE Sample*(n: LONGINT): Zlib.Bytes;
  VAR b: Zlib.Bytes; i, x: LONGINT;
BEGIN
  NEW(b, n); x := 12345;
  FOR i := 0 TO n - 1 DO
    x := (x * 1103515245 + 12345) MOD 2147483648;
    b[i] := CHR(ORD("a") + x DIV 65536 MOD 16)
  END;
  RETURN b
END Sample;

END Hex.
