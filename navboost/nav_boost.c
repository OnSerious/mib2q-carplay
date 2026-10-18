/*
 * nav_boost - raise the threads of named processes from one priority to another, and put back
 * exactly those threads later.
 *
 *   nav_boost <from> <to> <state> <name>...    boost
 *   nav_boost -r <state>                       restore
 *
 * Boost: for every running process whose executable basename equals one of <name>, every thread
 * whose base priority (not one inherited for the moment) is exactly <from> is set to <to>; its
 * scheduling policy and every other thread are left alone.  Each thread changed is appended to
 * <state> as "pid tid start_time from to".  Prints "<threads changed> <processes matched>".
 * Run again, it skips threads already at <to>, so <state> lists each thread once.
 *
 * Restore: every thread in <state> that still exists (same pid, tid and thread start time, so a
 * reused pid or tid is not touched) and still has base priority <to> goes back to <from>; a
 * thread that was at <to> before the boost was never recorded and keeps it.  <state> is removed.
 * Prints "<threads restored> <threads recorded>".
 *
 * Why: after power-on with a CarPlay dongle the session runs while native navigation starts.
 * Navigation's start-up threads run at the default priority 10 and wait on the eMMC driver and
 * io-pkt (EBNavFreezeLog: BusinessLogic@NavLibAdapter in REPLY to devb-sdmmc), which serve
 * requests at the caller's priority, behind every other priority-10 client.  NavSDK start took
 * 54-56 s instead of 2.8 s, and navigation missed its service-manager deadline.
 * carplay_monitor.sh raises navigation 10 -> 12 until it is up, then restores what it raised.
 *
 * QNX 6.5: /proc/<pid>/as, DCMD_PROC_MAPDEBUG_BASE (name), DCMD_PROC_TIDSTATUS (threads),
 * SchedSet (another process's thread; needs root, as the monitor runs).
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

/* Threads of one process moved from -> to, each recorded in state. */
static int retune(pid_t pid, int fd, int from, int to, FILE *state)
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
            if (SchedSet(pid, st.tid, SCHED_NOCHANGE, &sp) != -1) {
                fprintf(state, "%d %d %llu %d %d\n", (int)pid, (int)st.tid,
                        (unsigned long long)st.start_time, from, to);
                changed++;
            }
        }
        st.tid++;
    }
    return changed;
}

static int boost(int from, int to, const char *state_path, char **names, int count)
{
    int changed = 0, matched = 0;
    DIR *proc;
    struct dirent *de;
    FILE *state = fopen(state_path, "a");

    if (state == NULL) {
        perror("nav_boost: state");
        return 1;
    }
    proc = opendir("/proc");
    if (proc == NULL) {
        perror("nav_boost: /proc");
        fclose(state);
        return 1;
    }
    while ((de = readdir(proc)) != NULL) {
        char path[64];
        struct {
            procfs_debuginfo info;
            char buff[PATH_MAX];
        } name;
        pid_t pid;
        int fd;
        char *end;

        pid = (pid_t)strtol(de->d_name, &end, 10);
        if (*de->d_name == '\0' || *end != '\0' || pid <= 1) continue;
        snprintf(path, sizeof path, "/proc/%d/as", (int)pid);
        fd = open(path, O_RDONLY);
        if (fd < 0) continue;
        memset(&name, 0, sizeof name);
        if (devctl(fd, DCMD_PROC_MAPDEBUG_BASE, &name, sizeof name, NULL) == EOK
                && wanted(name.info.path, names, count)) {
            matched++;
            changed += retune(pid, fd, from, to, state);
        }
        close(fd);
    }
    closedir(proc);
    if (fclose(state) != 0) perror("nav_boost: state");
    printf("%d %d\n", changed, matched);
    return 0;
}

static int restore(const char *state_path)
{
    int restored = 0, recorded = 0, pid, tid, from, to;
    unsigned long long start;
    FILE *state = fopen(state_path, "r");

    if (state == NULL) {
        printf("0 0\n");                /* nothing was boosted */
        return 0;
    }
    while (fscanf(state, "%d %d %llu %d %d", &pid, &tid, &start, &from, &to) == 5) {
        char path[64];
        procfs_status st;
        int fd;

        recorded++;
        snprintf(path, sizeof path, "/proc/%d/as", pid);
        fd = open(path, O_RDONLY);
        if (fd < 0) continue;           /* process gone */
        memset(&st, 0, sizeof st);
        st.tid = tid;                   /* TIDSTATUS returns the first thread >= tid */
        if (devctl(fd, DCMD_PROC_TIDSTATUS, &st, sizeof st, NULL) == EOK
                && (int)st.tid == tid && (unsigned long long)st.start_time == start
                && st.real_priority == to) {
            struct sched_param sp;
            memset(&sp, 0, sizeof sp);
            sp.sched_priority = from;
            if (SchedSet(pid, tid, SCHED_NOCHANGE, &sp) != -1) restored++;
        }
        close(fd);
    }
    fclose(state);
    unlink(state_path);
    printf("%d %d\n", restored, recorded);
    return 0;
}

int main(int argc, char **argv)
{
    int from, to;

    if (argc == 3 && strcmp(argv[1], "-r") == 0)
        return restore(argv[2]);
    if (argc < 5 || parse_prio(argv[1], &from) != 0 || parse_prio(argv[2], &to) != 0) {
        fprintf(stderr, "usage: nav_boost <from 1-63> <to 1-63> <state> <name>...\n"
                        "       nav_boost -r <state>\n");
        return 2;
    }
    return boost(from, to, argv[3], argv + 4, argc - 4);
}
