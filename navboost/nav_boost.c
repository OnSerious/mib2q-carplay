/*
 * nav_boost - raise the threads of named processes from one priority to another, and put them
 * back later without touching threads that were at the higher priority before.
 *
 *   nav_boost <from> <to> <state> <name>...    boost
 *   nav_boost -r <state>                       restore
 *
 * Boost: for every running process whose executable basename equals one of <name>, every thread
 * whose base priority (not one inherited for the moment) is exactly <from> is set to <to>; its
 * scheduling policy and every other thread are left alone.  Prints "<threads changed> <processes
 * matched>".  The first time a process is seen, before any of its threads is changed, <state>
 * gets "P pid start from to" (start = process start time, so a reused pid is a new process) and
 * "N pid tid start" for each of its threads already at <to>: those keep <to> at restore (none
 * for a process spawned by a boosted one: it started at its parent's raised priority).  The
 * record goes out in one write() first; if it cannot be written whole, the file is cut back to
 * before it and that process and every later one is left alone (exit 1).
 *
 * Restore: in every recorded process that still runs, every thread at base priority <to> that is
 * not an "N" thread goes back to <from>.  That includes threads created by a boosted thread
 * (QNX threads inherit their creator's priority by default), which no scan ever saw at <from>.
 * A thread that sets itself to <to> while the boost runs is lowered too.  <state> is removed.
 * Prints "<threads restored> <processes recorded>".
 *
 * Why: after power-on with a CarPlay dongle the session runs while native navigation starts.
 * Navigation's start-up threads run at the default priority 10 and wait on the eMMC driver and
 * io-pkt (EBNavFreezeLog: BusinessLogic@NavLibAdapter in REPLY to devb-sdmmc), which serve
 * requests at the caller's priority, behind every other priority-10 client.  NavSDK start took
 * 54-56 s instead of 2.8 s, and navigation missed its service-manager deadline.
 * carplay_monitor.sh raises navigation 10 -> 12 until it is up, then restores it.
 *
 * QNX 6.5: /proc/<pid>/as, DCMD_PROC_MAPDEBUG_BASE (name), DCMD_PROC_INFO (process start),
 * DCMD_PROC_TIDSTATUS (threads), SchedSet (another process's thread; needs root, as the monitor
 * runs).
 *
 * Copyright (c) 2026
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include <devctl.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/neutrino.h>
#include <sys/procfs.h>
#include <unistd.h>

typedef struct { int pid; unsigned long long start; int from, to; } proc_rec;
typedef struct { int pid, tid; unsigned long long start; } native_rec;

static proc_rec *procs;
static int nprocs, procs_cap;
static native_rec *natives;
static int nnatives, natives_cap;

static int parse_prio(const char *s, int *out)
{
    char *end;
    long v = strtol(s, &end, 10);
    if (*s == '\0' || *end != '\0' || v < 1 || v > 63) return -1;
    *out = (int)v;
    return 0;
}

static const char *base_name(const char *path)
{
    const char *slash = strrchr(path, '/');
    return slash ? slash + 1 : path;
}

static int wanted(const char *path, char **names, int count)
{
    const char *b = base_name(path);
    int i;
    for (i = 0; i < count; i++)
        if (strcmp(b, names[i]) == 0) return 1;
    return 0;
}

static int add_proc(int pid, unsigned long long start, int from, int to)
{
    if (nprocs == procs_cap) {
        int cap = procs_cap ? procs_cap * 2 : 16;
        proc_rec *p = realloc(procs, cap * sizeof *p);
        if (p == NULL) return -1;
        procs = p;
        procs_cap = cap;
    }
    procs[nprocs].pid = pid;
    procs[nprocs].start = start;
    procs[nprocs].from = from;
    procs[nprocs].to = to;
    nprocs++;
    return 0;
}

static int add_native(int pid, int tid, unsigned long long start)
{
    if (nnatives == natives_cap) {
        int cap = natives_cap ? natives_cap * 2 : 64;
        native_rec *n = realloc(natives, cap * sizeof *n);
        if (n == NULL) return -1;
        natives = n;
        natives_cap = cap;
    }
    natives[nnatives].pid = pid;
    natives[nnatives].tid = tid;
    natives[nnatives].start = start;
    nnatives++;
    return 0;
}

static int known_proc(int pid, unsigned long long start)
{
    int i;
    for (i = 0; i < nprocs; i++)
        if (procs[i].pid == pid && procs[i].start == start) return 1;
    return 0;
}

static int is_native(int pid, int tid, unsigned long long start)
{
    int i;
    for (i = 0; i < nnatives; i++)
        if (natives[i].pid == pid && natives[i].tid == tid && natives[i].start == start) return 1;
    return 0;
}

/* Whole lines only: a line cut short by a failed write does not parse and is skipped. */
static int load_state(const char *path)
{
    char line[128];
    FILE *f = fopen(path, "r");
    if (f == NULL) return -1;
    while (fgets(line, sizeof line, f) != NULL) {
        int pid, tid, from, to;
        unsigned long long start;
        size_t len = strlen(line);
        if (len == 0 || line[len - 1] != '\n') continue;
        if (sscanf(line, "P %d %llu %d %d", &pid, &start, &from, &to) == 4) {
            if (add_proc(pid, start, from, to) != 0) break;
        } else if (sscanf(line, "N %d %d %llu", &pid, &tid, &start) == 3) {
            if (add_native(pid, tid, start) != 0) break;
        }
    }
    fclose(f);
    return 0;
}

static int proc_start(int fd, unsigned long long *start, int *parent)
{
    procfs_info info;
    memset(&info, 0, sizeof info);
    if (devctl(fd, DCMD_PROC_INFO, &info, sizeof info, NULL) != EOK) return -1;
    *start = (unsigned long long)info.start_time;
    if (parent != NULL) *parent = (int)info.parent;
    return 0;
}

static int boosted_pid(int pid)
{
    int i;
    for (i = 0; i < nprocs; i++)
        if (procs[i].pid == pid) return 1;
    return 0;
}

/* First sight of a process: its record and its threads already at <to>, written in one write()
 * before any change.  A process spawned by a boosted one (navStartup relaunching a child) starts
 * at its parent's raised priority, so none of its threads is recorded as already at <to>.  A
 * short or failed write is cut back to where this record began. */
static int record_proc(int sfd, int pid, int fd, unsigned long long start, int parent,
                       int from, int to)
{
    char buf[8192];
    procfs_status st;
    off_t off;
    int len, n;
    int inherited = boosted_pid(parent);

    len = snprintf(buf, sizeof buf, "P %d %llu %d %d\n", pid, start, from, to);
    memset(&st, 0, sizeof st);
    st.tid = 1;
    while (!inherited && devctl(fd, DCMD_PROC_TIDSTATUS, &st, sizeof st, NULL) == EOK) {
        if (st.real_priority == to) {
            n = snprintf(buf + len, sizeof buf - len, "N %d %d %llu\n",
                         pid, (int)st.tid, (unsigned long long)st.start_time);
            if (n < 0 || n >= (int)sizeof buf - len) return -1;     /* too many to record */
            len += n;
        }
        st.tid++;
    }
    if ((off = lseek(sfd, 0, SEEK_END)) < 0) return -1;
    n = (int)write(sfd, buf, (size_t)len);
    if (n != len) {
        if (n > 0 && ftruncate(sfd, off) != 0) perror("nav_boost: state cut back");
        return -1;
    }
    return add_proc(pid, start, from, to);
}

/* Threads of one process moved from -> to. */
static int retune(pid_t pid, int fd, int from, int to)
{
    procfs_status st;
    int changed = 0;
    memset(&st, 0, sizeof st);
    st.tid = 1;
    while (devctl(fd, DCMD_PROC_TIDSTATUS, &st, sizeof st, NULL) == EOK) {
        if (st.real_priority == from) {
            struct sched_param sp;
            memset(&sp, 0, sizeof sp);
            sp.sched_priority = to;
            if (SchedSet(pid, st.tid, SCHED_NOCHANGE, &sp) != -1) changed++;
        }
        st.tid++;
    }
    return changed;
}

static int boost(int from, int to, const char *state_path, char **names, int count)
{
    int changed = 0, matched = 0, failed = 0;
    DIR *proc;
    struct dirent *de;
    int sfd;

    load_state(state_path);
    sfd = open(state_path, O_WRONLY | O_APPEND | O_CREAT, 0644);
    if (sfd < 0) {
        perror("nav_boost: state");
        return 1;
    }
    proc = opendir("/proc");
    if (proc == NULL) {
        perror("nav_boost: /proc");
        close(sfd);
        return 1;
    }
    while (!failed && (de = readdir(proc)) != NULL) {
        char path[64];
        struct {
            procfs_debuginfo info;
            char buff[PATH_MAX];
        } name;
        pid_t pid;
        int fd;
        char *end;
        unsigned long long start;
        int parent;

        pid = (pid_t)strtol(de->d_name, &end, 10);
        if (*de->d_name == '\0' || *end != '\0' || pid <= 1) continue;
        snprintf(path, sizeof path, "/proc/%d/as", (int)pid);
        fd = open(path, O_RDONLY);
        if (fd < 0) continue;
        memset(&name, 0, sizeof name);
        if (devctl(fd, DCMD_PROC_MAPDEBUG_BASE, &name, sizeof name, NULL) == EOK
                && wanted(name.info.path, names, count)
                && proc_start(fd, &start, &parent) == 0) {
            matched++;
            if (!known_proc((int)pid, start)
                    && record_proc(sfd, (int)pid, fd, start, parent, from, to) != 0) {
                fprintf(stderr, "nav_boost: cannot record %d in %s, boost stopped\n",
                        (int)pid, state_path);
                failed = 1;
            } else {
                changed += retune(pid, fd, from, to);
            }
        }
        close(fd);
    }
    closedir(proc);
    close(sfd);
    printf("%d %d\n", changed, matched);
    return failed;
}

static int restore(const char *state_path)
{
    int restored = 0, i;

    if (load_state(state_path) != 0) {
        printf("0 0\n");                /* nothing was boosted */
        return 0;
    }
    for (i = 0; i < nprocs; i++) {
        char path[64];
        procfs_status st;
        unsigned long long start;
        int fd;

        snprintf(path, sizeof path, "/proc/%d/as", procs[i].pid);
        fd = open(path, O_RDONLY);
        if (fd < 0) continue;           /* process gone */
        if (proc_start(fd, &start, NULL) == 0 && start == procs[i].start) {
            memset(&st, 0, sizeof st);
            st.tid = 1;
            while (devctl(fd, DCMD_PROC_TIDSTATUS, &st, sizeof st, NULL) == EOK) {
                if (st.real_priority == procs[i].to
                        && !is_native(procs[i].pid, (int)st.tid,
                                      (unsigned long long)st.start_time)) {
                    struct sched_param sp;
                    memset(&sp, 0, sizeof sp);
                    sp.sched_priority = procs[i].from;
                    if (SchedSet(procs[i].pid, st.tid, SCHED_NOCHANGE, &sp) != -1) restored++;
                }
                st.tid++;
            }
        }
        close(fd);
    }
    unlink(state_path);
    printf("%d %d\n", restored, nprocs);
    return 0;
}

int main(int argc, char **argv)
{
    int from, to;

    nprocs = nnatives = 0;              /* one run per process; reset for the host test */
    if (argc == 3 && strcmp(argv[1], "-r") == 0)
        return restore(argv[2]);
    if (argc < 5 || parse_prio(argv[1], &from) != 0 || parse_prio(argv[2], &to) != 0) {
        fprintf(stderr, "usage: nav_boost <from 1-63> <to 1-63> <state> <name>...\n"
                        "       nav_boost -r <state>\n");
        return 2;
    }
    return boost(from, to, argv[3], argv + 4, argc - 4);
}
