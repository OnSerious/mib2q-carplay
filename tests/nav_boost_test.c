/*
 * navboost/nav_boost.c on the host against a fake QNX process table (tests/stubs/qnx, and
 * --wrap for open/close/opendir/readdir/closedir on /proc): boost raises only <from> threads and
 * records each process before changing it; restore lowers boosted, thread-inherited and
 * spawn-inherited threads, keeps threads that were at <to> before, skips a reused pid; a state
 * file that cannot be written stops the boost before any change.
 */
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

#include "devctl.h"
#include "sys/neutrino.h"
#include "sys/procfs.h"

int nav_boost_main(int argc, char **argv);

#define MAXP 8
#define MAXT 8
#define FD_BASE 1000

typedef struct { int tid; int prio; unsigned long long start; } fthread;
typedef struct {
    int used, pid, parent;
    unsigned long long start;
    const char *name;
    fthread t[MAXT];
    int nt;
} fproc;

static fproc P[MAXP];
static int checks;

static void check(int ok, const char *why)
{
    checks++;
    if (!ok) { fprintf(stderr, "FAIL: %s\n", why); exit(1); }
}

static fproc *proc_at(int i) { return (i >= 0 && i < MAXP && P[i].used) ? &P[i] : NULL; }

static fproc *add_proc(int slot, int pid, int parent, unsigned long long start, const char *name)
{
    fproc *p = &P[slot];
    memset(p, 0, sizeof *p);
    p->used = 1; p->pid = pid; p->parent = parent; p->start = start; p->name = name;
    return p;
}

static void add_thread(fproc *p, int tid, int prio, unsigned long long start)
{
    p->t[p->nt].tid = tid; p->t[p->nt].prio = prio; p->t[p->nt].start = start;
    p->nt++;
}

static int prio_of(int slot, int tid)
{
    int i;
    for (i = 0; i < P[slot].nt; i++) if (P[slot].t[i].tid == tid) return P[slot].t[i].prio;
    return -1;
}

/* ---- the QNX calls nav_boost makes ---- */

int devctl(int fd, int dcmd, void *data, size_t nbytes, int *info)
{
    fproc *p = proc_at(fd - FD_BASE);
    (void)nbytes; (void)info;
    if (p == NULL) return EBADF;
    if (dcmd == DCMD_PROC_MAPDEBUG_BASE) {
        char *path = ((procfs_debuginfo *)data)->path;
        sprintf(path, "/navigation/%s", p->name);
        return EOK;
    }
    if (dcmd == DCMD_PROC_INFO) {
        procfs_info *pi = data;
        pi->pid = p->pid; pi->parent = p->parent; pi->start_time = p->start;
        return EOK;
    }
    if (dcmd == DCMD_PROC_TIDSTATUS) {
        procfs_status *st = data;
        fthread *best = NULL;
        int i;
        for (i = 0; i < p->nt; i++)
            if (p->t[i].tid >= st->tid && (best == NULL || p->t[i].tid < best->tid)) best = &p->t[i];
        if (best == NULL) return ESRCH;
        st->pid = p->pid; st->tid = best->tid; st->start_time = best->start;
        st->priority = st->real_priority = (uint8_t)best->prio;
        return EOK;
    }
    return ENOSYS;
}

int SchedSet(pid_t pid, int tid, int policy, const struct sched_param *param)
{
    int i, j;
    (void)policy;
    for (i = 0; i < MAXP; i++) {
        if (!P[i].used || P[i].pid != pid) continue;
        for (j = 0; j < P[i].nt; j++)
            if (P[i].t[j].tid == tid) { P[i].t[j].prio = param->sched_priority; return 0; }
    }
    errno = ESRCH;
    return -1;
}

int __real_open(const char *path, int flags, ...);
int __wrap_open(const char *path, int flags, ...)
{
    int pid, i;
    char tail[8];
    if (sscanf(path, "/proc/%d/%7s", &pid, tail) == 2 && strcmp(tail, "as") == 0) {
        for (i = 0; i < MAXP; i++) if (P[i].used && P[i].pid == pid) return FD_BASE + i;
        errno = ENOENT;
        return -1;
    }
    return __real_open(path, flags, 0644);
}

int __real_close(int fd);
int __wrap_close(int fd) { return fd >= FD_BASE ? 0 : __real_close(fd); }

static struct dirent fake_ent;
static int fake_dir_pos;
static int fake_dir_token;
DIR *__real_opendir(const char *name);
DIR *__wrap_opendir(const char *name)
{
    if (strcmp(name, "/proc") != 0) return __real_opendir(name);
    fake_dir_pos = 0;
    return (DIR *)&fake_dir_token;
}

struct dirent *__real_readdir(DIR *d);
struct dirent *__wrap_readdir(DIR *d)
{
    if (d != (DIR *)&fake_dir_token) return __real_readdir(d);
    if (fake_dir_pos == 0) { fake_dir_pos++; strcpy(fake_ent.d_name, "self"); return &fake_ent; }
    while (fake_dir_pos - 1 < MAXP) {
        fproc *p = proc_at(fake_dir_pos - 1);
        fake_dir_pos++;
        if (p) { snprintf(fake_ent.d_name, sizeof fake_ent.d_name, "%d", p->pid); return &fake_ent; }
    }
    return NULL;
}

/* 0: pass through; 1: no space at all; 2: only half of the record fits */
static int fail_write;
ssize_t __real_write(int fd, const void *buf, size_t n);
ssize_t __wrap_write(int fd, const void *buf, size_t n)
{
    if (fail_write == 1) { errno = ENOSPC; return -1; }
    if (fail_write == 2) return __real_write(fd, buf, n / 2);
    return __real_write(fd, buf, n);
}

int __real_closedir(DIR *d);
int __wrap_closedir(DIR *d) { return d == (DIR *)&fake_dir_token ? 0 : __real_closedir(d); }

/* ---- driver ---- */

static int run(const char *a0, ...)
{
    char *argv[16];
    int argc = 0;
    va_list ap;
    argv[argc++] = "nav_boost";
    argv[argc++] = (char *)a0;
    va_start(ap, a0);
    while ((argv[argc] = va_arg(ap, char *)) != NULL) argc++;
    va_end(ap);
    /* nav_boost's counts and expected errors stay out of the test output */
    fflush(stdout);
    fflush(stderr);
    {
        int out = dup(1), err = dup(2), null = __real_open("/dev/null", O_WRONLY);
        int rc;
        dup2(null, 1);
        dup2(null, 2);
        rc = nav_boost_main(argc, argv);
        fflush(stdout);
        fflush(stderr);
        dup2(out, 1);
        dup2(err, 2);
        __real_close(null);
        __real_close(out);
        __real_close(err);
        return rc;
    }
}

int main(void)
{
    char state[] = "/tmp/nav_boost_test.XXXXXX";
    int fd = mkstemp(state);
    fproc *a, *b, *c;
    check(fd >= 0, "mkstemp");
    close(fd);
    unlink(state);

    /* navStartup: t1 at 10, t2 already at 12 (stock), t3 at 15; an unrelated process at 10. */
    a = add_proc(0, 100, 1, 5000, "navStartup");
    add_thread(a, 1, 10, 5001); add_thread(a, 2, 12, 5002); add_thread(a, 3, 15, 5003);
    c = add_proc(2, 300, 1, 7000, "io-pkt");
    add_thread(c, 1, 10, 7001);

    check(run("10", "12", state, "navStartup", "AppStartATF", NULL) == 0, "boost 1");
    check(prio_of(0, 1) == 12 && prio_of(0, 2) == 12 && prio_of(0, 3) == 15, "only 10 raised");
    check(prio_of(2, 1) == 10, "unrelated process untouched");

    /* While boosted: navStartup's thread t1 creates t4 (inherits 12) and spawns AppStartATF,
     * whose threads start at 12 too; AppStartATF then adds a thread at 10. */
    add_thread(a, 4, 12, 5004);
    b = add_proc(1, 200, 100, 6000, "AppStartATF");
    add_thread(b, 1, 12, 6001); add_thread(b, 2, 12, 6002);
    check(run("10", "12", state, "navStartup", "AppStartATF", NULL) == 0, "boost 2");
    add_thread(b, 3, 10, 6003);
    check(run("10", "12", state, "navStartup", "AppStartATF", NULL) == 0, "boost 3");
    check(prio_of(1, 3) == 12, "new 10 thread raised");

    check(run("-r", state, NULL) == 0, "restore");
    check(prio_of(0, 1) == 10, "boosted thread restored");
    check(prio_of(0, 2) == 12, "thread at 12 before the boost kept");
    check(prio_of(0, 3) == 15, "other priority untouched");
    check(prio_of(0, 4) == 10, "thread inherited from a boosted thread restored");
    check(prio_of(1, 1) == 10 && prio_of(1, 2) == 10, "spawned child's inherited threads restored");
    check(prio_of(1, 3) == 10, "child's boosted thread restored");
    check(access(state, F_OK) != 0, "state removed");

    /* pid reuse: the recorded process is gone and a new one has its pid. */
    memset(P, 0, sizeof P);
    a = add_proc(0, 100, 1, 5000, "navStartup");
    add_thread(a, 1, 10, 5001);
    check(run("10", "12", state, "navStartup", NULL) == 0, "boost reuse");
    a = add_proc(0, 100, 1, 9000, "navStartup");
    add_thread(a, 1, 12, 9001);
    check(run("-r", state, NULL) == 0, "restore reuse");
    check(prio_of(0, 1) == 12, "reused pid untouched");

    /* restore without a state file: nothing to do */
    check(run("-r", state, NULL) == 0, "restore without state");

    /* state that cannot be written: nothing changes, exit 1 */
    memset(P, 0, sizeof P);
    a = add_proc(0, 100, 1, 5000, "navStartup");
    add_thread(a, 1, 10, 5001);
    for (fail_write = 1; fail_write <= 2; fail_write++) {
        FILE *f;
        long size = -1;
        check(run("10", "12", state, "navStartup", NULL) == 1, "write failure reported");
        check(prio_of(0, 1) == 10, "nothing raised without a record");
        f = fopen(state, "r");
        if (f) { fseek(f, 0L, SEEK_END); size = ftell(f); fclose(f); }
        check(size == 0, "partial record cut back");
    }
    fail_write = 0;
    check(run("10", "12", state, "navStartup", NULL) == 0 && prio_of(0, 1) == 12, "next run boosts");
    check(run("-r", state, NULL) == 0 && prio_of(0, 1) == 10, "and restores");

    printf("nav_boost_test: raise/record order, restore of boosted, thread- and spawn-inherited "
           "threads, stock 12 kept, pid reuse, write failure, %d checks PASS\n", checks);
    return 0;
}
