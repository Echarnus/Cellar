/*
 * cellar-mipfix — replaces -[MTLBlitCommandEncoder generateMipmapsForTexture:] on block-compressed
 * textures, which Metal does not support, with mips built on the CPU.
 *
 * Under D3DMetal, Custom Shaders Patch for Assetto Corsa ends up asking for mip generation on BC1,
 * BC2 and BC3 texture arrays. Instead of refusing, Apple's Metal compiler service crashes
 * (null pointer in AGCLLVMTextureFetchFragmentShader::buildMRCDownsampleBlitShader), the GPU
 * driver aborts in the game, Wine's abort handler deadlocks on that non-Wine thread, and the game
 * hangs while loading. These are textures shipped without mips (Kunos' DXT1/DXT5 car textures), so
 * merely skipping the call leaves their lower levels undefined: garbage at a distance or a grazing
 * angle. The levels are built on the CPU instead, for textures the CPU can see (queue_levels);
 * other compressed textures are still skipped.
 *
 * Active in the game's process only (the exe Cellar names in CELLAR_APP_EXE). The blit encoders
 * live in the GPU driver bundle and in MetalTools (the validation layer's wrappers); the driver
 * is dlopen'd and its classes are not known yet at its own dyld callback, so it is scanned again
 * at each later one until they are. MIPFIX_LOG=<file> (settable in a profile's [env]) logs what it does.
 */
#include <crt_externs.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int cellar_bc_next_level(const unsigned char *src, unsigned long w, unsigned long h, unsigned char *dst, int bc3);  /* cellar-bc.c */
typedef void (*gen_fn)(id, SEL, id);
#define MAX_HOOKS 16
static struct { Class cls; gen_fn original; } hooks[MAX_HOOKS];
static int hook_count;
static FILE *log_file;
static const struct mach_header *pending_driver;

typedef struct { unsigned long x, y, z; } mtl_triple;
typedef struct { mtl_triple origin, size; } mtl_region;
static unsigned long ulv(id o, const char *s) { return ((unsigned long (*)(id, SEL))objc_msgSend)(o, sel_registerName(s)); }

/* Bytes per 4x4 block of a BC format (MTLPixelFormat 130-143), 0 for other compressed formats. */
static unsigned long bc_block_bytes(unsigned long format)
{
    if (format == 130 || format == 131 || format == 140 || format == 141) return 8;   /* BC1, BC4 */
    return format >= 132 && format <= 143 ? 16 : 0;                                   /* BC2, BC3, BC5-BC7 */
}

/* Writes levels 1+ of a CPU-visible BC texture, from `top` (level 0 of every slice, one after the
 * other). BC1 and BC3 (DXT1/DXT5, what Kunos ships) are decoded, filtered 2x2 and encoded again
 * (cellar-bc.c); other BC formats are block subsampled: block (x, y) of a level is block (2x, 2y)
 * of the level above. Either way the levels hold real texture data instead of staying undefined. */
static void build_levels(id texture, unsigned long format, unsigned long block, const unsigned char *top)
{
    unsigned long w = ulv(texture, "width"), h = ulv(texture, "height");
    unsigned long levels = ulv(texture, "mipmapLevelCount"), slices = ulv(texture, "arrayLength");
    unsigned long bw = (w + 3) / 4, bh = (h + 3) / 4, slice_bytes = bw * bh * block;
    unsigned char *above = malloc(slice_bytes), *below = malloc(slice_bytes);
    SEL put = sel_registerName("replaceRegion:mipmapLevel:slice:withBytes:bytesPerRow:bytesPerImage:");
    int bc3 = format == 134 || format == 135, codec = format == 130 || format == 131 || bc3;
    for (unsigned long slice = 0; above && below && slice < (slices ? slices : 1); slice++) {
        memcpy(above, top + slice * slice_bytes, slice_bytes);
        unsigned long sw = w, sh = h;
        for (unsigned long level = 1; level < levels; level++) {
            unsigned long sbw = (sw + 3) / 4, sbh = (sh + 3) / 4;
            unsigned long lw = sw / 2 ? sw / 2 : 1, lh = sh / 2 ? sh / 2 : 1;
            unsigned long lbw = (lw + 3) / 4, lbh = (lh + 3) / 4;
            if (!(codec && cellar_bc_next_level(above, sw, sh, below, bc3)))
                for (unsigned long y = 0; y < lbh; y++)
                    for (unsigned long x = 0; x < lbw; x++) {
                        unsigned long sx = 2 * x < sbw ? 2 * x : sbw - 1, sy = 2 * y < sbh ? 2 * y : sbh - 1;
                        memcpy(below + (y * lbw + x) * block, above + (sy * sbw + sx) * block, block);
                    }
            mtl_region region = { {0, 0, 0}, {lw, lh, 1} };
            ((void (*)(id, SEL, mtl_region, unsigned long, unsigned long, const void *, unsigned long, unsigned long))objc_msgSend)(
                texture, put, region, level, slice, below, lbw * block, lbw * lbh * block);
            unsigned char *t = above; above = below; below = t;
            sw = lw; sh = lh;
        }
    }
    free(above); free(below);
}

/* Level 0 must be read once the GPU has written it: the game's upload may still be queued when it
 * asks for mips (measured up to ~110 ms), and reading early would build the mips from whatever the
 * memory held before. So the encoder itself copies level 0 into a shared buffer and then sets
 * a flag byte after it; a worker thread waits for the flag, builds the levels and writes them. */
typedef struct job { id texture, buffer; unsigned long format, block, flag; struct job *next; } job;
static job *jobs;
static pthread_mutex_t jobs_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t jobs_ready = PTHREAD_COND_INITIALIZER;
static pthread_t worker;
static int worker_started;

static id retain(id o) { return ((id (*)(id, SEL))objc_msgSend)(o, sel_registerName("retain")); }
static void release(id o) { ((void (*)(id, SEL))objc_msgSend)(o, sel_registerName("release")); }

static void *mip_worker(void *unused)
{
    (void)unused;
    for (;;) {
        pthread_mutex_lock(&jobs_lock);
        while (!jobs) pthread_cond_wait(&jobs_ready, &jobs_lock);
        job *j = jobs; jobs = j->next;
        pthread_mutex_unlock(&jobs_lock);
        volatile unsigned char *data = ((unsigned char *(*)(id, SEL))objc_msgSend)(j->buffer, sel_registerName("contents"));
        int waited = 0;  /* ms; a command buffer that is never committed would leave the flag unset */
        while (data[j->flag] != 1 && waited < 30000) { usleep(1000); waited++; }
        if (data[j->flag] == 1) build_levels(j->texture, j->format, j->block, (const unsigned char *)data);
        if (log_file) { fprintf(log_file, "cellar-mipfix: format %lu %s after %d ms\n", j->format, data[j->flag] == 1 ? "built" : "timed out", waited); fflush(log_file); }
        release(j->texture); release(j->buffer); free(j);
    }
    return NULL;
}

/* Queues the CPU-built levels of a BC texture; returns 0 if it cannot (texture not CPU-visible). */
static int queue_levels(id encoder, id texture, unsigned long format, unsigned long block)
{
    if (ulv(texture, "storageMode") == 2 || ulv(texture, "mipmapLevelCount") < 2) return 0;  /* MTLStorageModePrivate */
    unsigned long w = ulv(texture, "width"), h = ulv(texture, "height"), slices = ulv(texture, "arrayLength");
    if (!slices) slices = 1;
    unsigned long bw = (w + 3) / 4, bh = (h + 3) / 4, slice_bytes = bw * bh * block, total = slice_bytes * slices;
    id device = ((id (*)(id, SEL))objc_msgSend)(texture, sel_registerName("device"));
    id buffer = ((id (*)(id, SEL, unsigned long, unsigned long))objc_msgSend)(device, sel_registerName("newBufferWithLength:options:"), total + 1, 0);
    job *j = buffer ? calloc(1, sizeof *j) : NULL;
    if (!j) { if (buffer) release(buffer); return 0; }
    SEL copy = sel_registerName("copyFromTexture:sourceSlice:sourceLevel:sourceOrigin:sourceSize:toBuffer:destinationOffset:destinationBytesPerRow:destinationBytesPerImage:");
    mtl_triple origin = { 0, 0, 0 }, size = { w, h, 1 };
    for (unsigned long slice = 0; slice < slices; slice++)
        ((void (*)(id, SEL, id, unsigned long, unsigned long, mtl_triple, mtl_triple, id, unsigned long, unsigned long, unsigned long))objc_msgSend)(
            encoder, copy, texture, slice, 0, origin, size, buffer, slice * slice_bytes, bw * block, slice_bytes);
    struct { unsigned long location, length; } flag_range = { total, 1 };
    ((void (*)(id, SEL, id, typeof(flag_range), unsigned char))objc_msgSend)(encoder, sel_registerName("fillBuffer:range:value:"), buffer, flag_range, 1);
    j->texture = retain(texture); j->buffer = buffer; j->format = format; j->block = block; j->flag = total;
    pthread_mutex_lock(&jobs_lock);
    job **tail = &jobs;
    while (*tail) tail = &(*tail)->next;
    *tail = j;
    if (!worker_started) worker_started = pthread_create(&worker, NULL, mip_worker, NULL) == 0;
    pthread_cond_signal(&jobs_ready);
    pthread_mutex_unlock(&jobs_lock);
    return 1;
}

static gen_fn original_for(id self)
{
    for (Class c = object_getClass(self); c; c = class_getSuperclass(c))
        for (int i = 0; i < hook_count; i++)
            if (hooks[i].cls == c) return hooks[i].original;
    return NULL;
}

static void mipfix_generate(id self, SEL cmd, id texture)
{
    unsigned long format = ((unsigned long (*)(id, SEL))objc_msgSend)(texture, sel_registerName("pixelFormat"));
    /* MTLPixelFormat 130 (BC1) to 235 (ASTC HDR): the compressed formats (BC, PVRTC, ETC/EAC, ASTC). */
    if (format >= 130 && format <= 235) {
        unsigned long block = bc_block_bytes(format);
        int queued = block && queue_levels(self, texture, format, block);
        if (log_file && !queued) { fprintf(log_file, "cellar-mipfix: format %lu skipped\n", format); fflush(log_file); }
        return;
    }
    gen_fn original = original_for(self);
    if (original) original(self, cmd, texture);
}

/* Hooks the image's blit encoders; returns how many classes the runtime knows for it. */
static unsigned int scan_image(const char *path)
{
    unsigned int count = 0;
    const char **names = objc_copyClassNamesForImage(path, &count);
    SEL sel = sel_registerName("generateMipmapsForTexture:");
    for (unsigned int i = 0; i < count && hook_count < MAX_HOOKS; i++) {
        if (!strstr(names[i], "Blit")) continue;
        Class cls = objc_getClass(names[i]);
        unsigned int n = 0;
        Method *methods = cls ? class_copyMethodList(cls, &n) : NULL;  /* this class's own methods only */
        for (unsigned int m = 0; m < n; m++)
            if (method_getName(methods[m]) == sel && method_getImplementation(methods[m]) != (IMP)mipfix_generate) {
                hooks[hook_count].cls = cls;
                hooks[hook_count].original = (gen_fn)method_setImplementation(methods[m], (IMP)mipfix_generate);
                hook_count++;
                if (log_file) { fprintf(log_file, "cellar-mipfix: hooked %s\n", names[i]); fflush(log_file); }
            }
        free(methods);
    }
    free(names);
    return count;
}

static void image_added(const struct mach_header *mh, intptr_t slide)
{
    (void)slide;
    Dl_info info;
    if (pending_driver && dladdr(pending_driver, &info) && info.dli_fname && scan_image(info.dli_fname))
        pending_driver = NULL;
    if (!dladdr(mh, &info) || !info.dli_fname) return;
    int driver = strstr(info.dli_fname, "/Extensions/AGX") != NULL;
    if (!driver && !strstr(info.dli_fname, "Metal")) return;
    if (!scan_image(info.dli_fname) && driver) pending_driver = mh;
}

__attribute__((constructor))
static void cellar_mipfix_init(void)
{
    const char *exe = getenv("CELLAR_APP_EXE");
    char **argv = *_NSGetArgv();
    /* Under Wine, argv[1] is the Windows exe. */
    if (!exe || !*exe || !argv || !argv[0] || !argv[1] || !strcasestr(argv[1], exe)) return;
    const char *log_path = getenv("MIPFIX_LOG");
    if (log_path && *log_path) log_file = fopen(log_path, "a");
    _dyld_register_func_for_add_image(image_added);
}
