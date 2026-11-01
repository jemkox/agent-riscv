// picolibc stdio "no sys" glue for the RV32 Doom testbench (M10c).
// The WAD lives at a fixed virtual address in CPU RAM (loaded pre-reset
// by the Verilated main); fopen serves it from there. stdout/stderr
// write bytes through the memory-mapped UART at 0x1000_0000.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define UART_ADDR 0x1FF00000u
#define WAD_VADDR 0x00C00000u
#define WAD_LEN   4196020u

static char sinkbuf[4096];

/* picolibc tinystdio's fmemopen mis-sets the content length for "r"
   streams in this build, so provide our own FILE subclass matching the
   layout fmemopen uses: +0 r0 | +4 mode | +8 put | +12 get | +16 flush
   | +20 close | +24 seek | +32 buf | +36 content | +40 cap | +44 pos
   | +48 extra flag byte (52 bytes total). */
typedef struct ms_tag {
    void *r0;
    unsigned char mode;
    char pad1[3];
    int (*put)(int c, FILE *f);
    int (*get)(FILE *f);
    int (*flush)(FILE *f);
    int (*close)(FILE *f);
    int (*seek)(FILE *f, long off, int dir);
    void *r1;
    unsigned char *buf;
    size_t content;
    size_t cap;
    size_t pos;
    unsigned char fl;
    char pad2[3];
} mstream_t;
static char ms_lay_a[(sizeof(mstream_t) == 52) ? 1 : -1];
static char ms_lay_b[(__builtin_offsetof(mstream_t, put) == 8) ? 1 : -1];
static char ms_lay_c[(__builtin_offsetof(mstream_t, get) == 12) ? 1 : -1];
static char ms_lay_d[(__builtin_offsetof(mstream_t, flush) == 16) ? 1 : -1];
static char ms_lay_e[(__builtin_offsetof(mstream_t, close) == 20) ? 1 : -1];
static char ms_lay_f[(__builtin_offsetof(mstream_t, seek) == 24) ? 1 : -1];
static char ms_lay_g[(__builtin_offsetof(mstream_t, buf) == 32) ? 1 : -1];
static char ms_lay_h[(__builtin_offsetof(mstream_t, pos) == 44) ? 1 : -1];

static int ms_get(FILE *f)
{
    mstream_t *s = (mstream_t *)f;
    if (!(s->mode & 1)) return -1;
    if (s->pos >= s->content) return -2;
    return s->buf[s->pos++];
}
static int ms_put(int c, FILE *f)
{
    mstream_t *s = (mstream_t *)f;
    if (!(s->mode & 2)) return -1;
    if (s->pos >= s->cap) return -2;
    s->buf[s->pos++] = (unsigned char)c;
    if (s->pos > s->content) s->content = s->pos;
    return (unsigned char)c;
}
static int ms_flush(FILE *f) { (void)f; return 0; }
static int ms_close(FILE *f) { mstream_t *s = (mstream_t *)f; free(s); return 0; }
static int ms_seek(FILE *f, long off, int dir)
{
    mstream_t *s = (mstream_t *)f;
    long o = off;
    if (dir == 1) o += (long)s->pos;
    else if (dir == 2) o += (long)s->content;
    if (o < 0) return -1;
    if ((unsigned long)o > s->cap) return -1;
    s->pos = (unsigned long)o;
    return 0;
}
static mstream_t *ms_new(unsigned char *b, size_t len, size_t content)
{
    mstream_t *s = malloc(sizeof(mstream_t));
    if (!s) return 0;
    memset(s, 0, sizeof(mstream_t));
    s->mode = 3;
    s->put = ms_put; s->get = ms_get; s->flush = ms_flush;
    s->close = ms_close; s->seek = ms_seek;
    s->buf = b; s->cap = len; s->content = content; s->pos = 0;
    return s;
}

void mark(unsigned c)
{
    *(volatile unsigned char *)(uintptr_t)UART_ADDR = (unsigned char)c;
}

static int uart_put(char c, FILE *f)
{
    (void)f;
    *(volatile unsigned char *)(uintptr_t)UART_ADDR = (unsigned char)c;
    return (unsigned char)c;
}

static int uart_get(FILE *f) { return EOF; }
static int uart_flush(FILE *f) { return 0; }

// stdout/stderr are defined (as zero cells) in stdout_sym.s; fill them in
// before main via a constructor.
extern FILE *const stdout;
extern FILE *const stderr;

void picolibc_init_streams(void) __attribute__((constructor));
void picolibc_init_streams(void)
{
    FILE *volatile *pp;
    pp = (FILE *volatile *)(void *)&stdout;
    *pp = fdevopen(uart_put, uart_get, uart_flush);
    pp = (FILE *volatile *)(void *)&stderr;
    *pp = fdevopen(uart_put, uart_get, uart_flush);
}

/* legacy fd hooks: fopen calls open(), which here returns a small integer
   handle cast to FILE *; fdopen wraps it in the __bufio_* layer, whose
   get/put/seek call read()/write()/lseek()/close() with that fd. */
static struct fd_e {
    const unsigned char *buf;
    unsigned len;
    unsigned pos;
} fdtab[8];

static int fd_alloc(const unsigned char *b, unsigned len, unsigned pos)
{
    for (int i = 1; i < 8; i++)
        if (!fdtab[i].buf) {
            fdtab[i].buf = b; fdtab[i].len = len; fdtab[i].pos = pos;
            return i;
        }
    return 0;
}

/* Only the shareware IWAD exists: answering every *.wad name made the IWAD search find "doom2.wad". */
static int wad_ok_name(const char *name)
{
    if (!name || !(strstr(name, ".wad") || strstr(name, ".WAD"))) return 0;
    return strstr(name, "doom1") || strstr(name, "DOOM1");
}

FILE *open(const char *name, int mode, int isdir)
{
    (void)isdir;
    if (wad_ok_name(name))
        return (FILE *)(uintptr_t)fd_alloc(
            (const unsigned char *)(uintptr_t)WAD_VADDR, WAD_LEN, 0);
    if (mode & 2) // write sink for config files
        return (FILE *)(uintptr_t)fd_alloc(sinkbuf, sizeof sinkbuf, 0);
    return 0;
}

int close(int fd)
{
    if (fd < 1 || fd > 7) return -1;
    fdtab[fd].pos = 0;
    return 0;
}

int write(int fd, const unsigned char *buf, int n)
{
    if (fd < 1 || fd > 7 || !fdtab[fd].buf) return -1;
    int left = (int)fdtab[fd].len - (int)fdtab[fd].pos;
    int m = n < left ? n : left;
    for (int i = 0; i < m; i++)
        ((unsigned char *)fdtab[fd].buf)[fdtab[fd].pos + i] = buf[i];
    fdtab[fd].pos += m;
    return m;
}

int read(int fd, unsigned char *buf, int n)
{
    if (fd < 1 || fd > 7 || !fdtab[fd].buf) return -1;
    int left = (int)fdtab[fd].len - (int)fdtab[fd].pos;
    if (left <= 0) return 0;
    int m = n < left ? n : left;
    for (int i = 0; i < m; i++)
        buf[i] = fdtab[fd].buf[fdtab[fd].pos + i];
    fdtab[fd].pos += m;
    return m;
}

int lseek(int fd, long off, int dir)
{
    if (fd < 1 || fd > 7) return -1;
    unsigned p = fdtab[fd].pos, len = fdtab[fd].len;
    if (dir == 0) p = (unsigned)off;
    else if (dir == 1) p = p + (unsigned)off;
    else p = len + (unsigned)off;
    if (p > len) p = len;
    fdtab[fd].pos = p;
    return (int)p;
}

extern void _exit(int); /* exit_rv.S: ecall a7=93 */
void exit(int code) { _exit(code); }

extern char __heap_start__[];
extern char __heap_end__[];
static char *heap_cur;
void *sbrk(void *extra);
void *_sbrk(void *extra);
void *sbrk(void *extra)
{
    uintptr_t n = (uintptr_t)extra;
    char *old = heap_cur ? heap_cur : __heap_start__;
    char *nw = old + n;
    if ((void *)nw > (void *)__heap_end__)
        return (void *)-1;
    heap_cur = nw;
    return old;
}
void *_sbrk(void *extra) { return sbrk(extra); }
