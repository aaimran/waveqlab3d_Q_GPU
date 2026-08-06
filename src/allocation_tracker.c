#include <stdatomic.h>
#include <execinfo.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>

static _Atomic unsigned long long allocation_calls = 0;
static _Atomic int tracking = 0;
static _Atomic unsigned int traces_printed = 0;
static _Thread_local int tracing = 0;

static void trace_allocation(const char *kind) {
    void *frames[16];
    int frame_count;
    unsigned int trace_number;

    if (tracing) return;
    trace_number = atomic_fetch_add_explicit(&traces_printed, 1, memory_order_relaxed);
    if (trace_number >= 12) return;
    tracing = 1;
    frame_count = backtrace(frames, 16);
    fprintf(stderr, "WQL3D allocation trace %u (%s):\n", trace_number + 1, kind);
    backtrace_symbols_fd(frames, frame_count, 2);
    tracing = 0;
}

void *__real_malloc(size_t size);
void *__real_calloc(size_t count, size_t size);
void *__real_realloc(void *pointer, size_t size);

void *__wrap_malloc(size_t size) {
    if (atomic_load_explicit(&tracking, memory_order_relaxed) && !tracing) {
        atomic_fetch_add_explicit(&allocation_calls, 1, memory_order_relaxed);
        trace_allocation("malloc");
    }
    return __real_malloc(size);
}

void *__wrap_calloc(size_t count, size_t size) {
    if (atomic_load_explicit(&tracking, memory_order_relaxed) && !tracing) {
        atomic_fetch_add_explicit(&allocation_calls, 1, memory_order_relaxed);
        trace_allocation("calloc");
    }
    return __real_calloc(count, size);
}

void *__wrap_realloc(void *pointer, size_t size) {
    if (atomic_load_explicit(&tracking, memory_order_relaxed) && !tracing) {
        atomic_fetch_add_explicit(&allocation_calls, 1, memory_order_relaxed);
        trace_allocation("realloc");
    }
    return __real_realloc(pointer, size);
}

void wql3d_allocation_tracker_begin(void) {
    atomic_store_explicit(&allocation_calls, 0, memory_order_relaxed);
    atomic_store_explicit(&traces_printed, 0, memory_order_relaxed);
    atomic_store_explicit(&tracking, 1, memory_order_release);
}

unsigned long long wql3d_allocation_tracker_end(void) {
    atomic_store_explicit(&tracking, 0, memory_order_release);
    return atomic_load_explicit(&allocation_calls, memory_order_relaxed);
}
