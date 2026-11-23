/* ZlibThin.c - the part of ZlibThin.Mod written in C.

   poc compiles a module's sibling .c with clang whenever it compiles the
   module, and links its object with the program. Everything here is what
   ZlibThin.Mod cannot declare as a plain ["C"] external procedure:

   - z_stream, allocated, read and written here, so clang computes its
     layout from the installed <zlib.h> and no Oberon record mirrors it;
   - deflateInit2 and inflateInit2, which are macros (they pass
     ZLIB_VERSION and sizeof(z_stream) to deflateInit2_ and inflateInit2_);
   - the functions that take or return a uLong, whose width follows the
     host's long (64 bits on LP64, 32 on i386), carried here as int64_t;
   - the values of zlib's #defines, for the test that checks ZlibThin.Mod's
     constants against them.

   The interface is in fixed-width types only, so it means the same under
   both of poc's size models: int32_t for a C int, int64_t for a count or
   a uLong, intptr_t for a pointer (SYSTEM.ADDRESS on the Oberon side).

   The C names start with zt_, apart from zlib's; the linker names
   start with "ZlibThin.-": "-" cannot be in an Oberon name, so
   no module's procedure or variable can be called the same. */

#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <zlib.h>

#define NAME(n) __asm__("ZlibThin.-" n)

typedef intptr_t address;

#define STRM(s) ((z_stream *)(s))

/* ---- Streams ---- */

/* A zeroed z_stream: zalloc, zfree and opaque Z_NULL ask zlib for its
   default allocator, and next_in Z_NULL with avail_in 0 is what
   inflateInit2 requires. 0 if calloc fails. */
address zt_stream_new(void) NAME("stream-new");
address zt_stream_new(void)
{
	return (address)calloc(1, sizeof(z_stream));
}

void zt_stream_free(address s) NAME("stream-free");
void zt_stream_free(address s)
{
	free(STRM(s));
}

int32_t zt_deflate_init(address s, int32_t level, int32_t window_bits, int32_t mem_level,
		     int32_t strategy) NAME("deflate-init");
int32_t zt_deflate_init(address s, int32_t level, int32_t window_bits, int32_t mem_level,
		     int32_t strategy)
{
	return deflateInit2(STRM(s), level, Z_DEFLATED, window_bits, mem_level, strategy);
}

int32_t zt_inflate_init(address s, int32_t window_bits) NAME("inflate-init");
int32_t zt_inflate_init(address s, int32_t window_bits)
{
	return inflateInit2(STRM(s), window_bits);
}

/* avail_in and avail_out are uInt; ZlibThin.Mod's callers never pass
   more than MaxAvail, which fits, so the conversion loses nothing. */
void zt_set_input(address s, address next, int64_t avail) NAME("set-input");
void zt_set_input(address s, address next, int64_t avail)
{
	STRM(s)->next_in = (Bytef *)next;
	STRM(s)->avail_in = (uInt)avail;
}

void zt_set_output(address s, address next, int64_t avail) NAME("set-output");
void zt_set_output(address s, address next, int64_t avail)
{
	STRM(s)->next_out = (Bytef *)next;
	STRM(s)->avail_out = (uInt)avail;
}

int64_t zt_avail_in(address s) NAME("avail-in");
int64_t zt_avail_in(address s)
{
	return STRM(s)->avail_in;
}

int64_t zt_avail_out(address s) NAME("avail-out");
int64_t zt_avail_out(address s)
{
	return STRM(s)->avail_out;
}

/* total_in and total_out are uLong, so they wrap at 4 GB where long has
   32 bits. */
int64_t zt_total_in(address s) NAME("total-in");
int64_t zt_total_in(address s)
{
	return (int64_t)STRM(s)->total_in;
}

int64_t zt_total_out(address s) NAME("total-out");
int64_t zt_total_out(address s)
{
	return (int64_t)STRM(s)->total_out;
}

/* zlib's message for the last error, a static string, or 0. */
address zt_msg(address s) NAME("msg");
address zt_msg(address s)
{
	return (address)STRM(s)->msg;
}

int64_t zt_deflate_bound(address s, int64_t source_len) NAME("deflate-bound");
int64_t zt_deflate_bound(address s, int64_t source_len)
{
	return (int64_t)deflateBound(STRM(s), (uLong)source_len);
}

/* ---- Checksums ---- */

int64_t zt_adler32(int64_t adler, address buf, address len) NAME("adler32");
int64_t zt_adler32(int64_t adler, address buf, address len)
{
	return (int64_t)adler32_z((uLong)adler, (const Bytef *)buf, (z_size_t)len);
}

int64_t zt_crc32(int64_t crc, address buf, address len) NAME("crc32");
int64_t zt_crc32(int64_t crc, address buf, address len)
{
	return (int64_t)crc32_z((uLong)crc, (const Bytef *)buf, (z_size_t)len);
}

/* ---- Constants ---- */

/* The value of zlib's #define number which, in the order of
   ZlibThin.Mod's TestConstant list; INT32_MIN for an unknown number. */
int32_t zt_constant(int32_t which) NAME("constant");
int32_t zt_constant(int32_t which)
{
	static const int32_t values[] = {
		Z_OK, Z_STREAM_END, Z_NEED_DICT, Z_ERRNO, Z_STREAM_ERROR,
		Z_DATA_ERROR, Z_MEM_ERROR, Z_BUF_ERROR, Z_VERSION_ERROR,
		Z_NO_FLUSH, Z_PARTIAL_FLUSH, Z_SYNC_FLUSH, Z_FULL_FLUSH, Z_FINISH,
		Z_BLOCK,
		Z_NO_COMPRESSION, Z_BEST_SPEED, Z_BEST_COMPRESSION,
		Z_DEFAULT_COMPRESSION,
		Z_FILTERED, Z_HUFFMAN_ONLY, Z_RLE, Z_FIXED, Z_DEFAULT_STRATEGY,
		MAX_WBITS, MAX_MEM_LEVEL,
	};

	if (which < 0 || (size_t)which >= sizeof values / sizeof values[0])
		return INT32_MIN;
	return values[which];
}

/* UINT_MAX, the most avail_in or avail_out can hold. */
int64_t zt_uint_max(void) NAME("uint-max");
int64_t zt_uint_max(void)
{
	return UINT_MAX;
}
