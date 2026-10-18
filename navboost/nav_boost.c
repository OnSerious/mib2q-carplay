/*
 * nav_boost - move the threads of named processes from one priority to another.
 *
 *   nav_boost <from> <to> <name>...
 *
 * For every running process whose executable basename equals one of <name>, every thread
 * whose current priority is exactly <from> is set to <to>; its scheduling policy and every
 * thread at another priority are left alone.  Prints "<threads changed> <processes matched>".
 *
 * Why: after power-on with a CarPlay dongle the session runs while native navigation starts.
 * Navigation's start-up threads run at the default priority 10 and wait on the eMMC driver and
 * io-pkt (EBNavFreezeLog: BusinessLogic@NavLibAdapter in REPLY to devb-sdmmc), which serve
 * requests at the caller's priority, behind every other priority-10 client.  NavSDK start took
 * 54-56 s instead of 2.8 s, and navigation missed its service-manager deadline.
 * carplay_monitor.sh raises navigation 10 -> 12 until it is up, then puts it back 12 -> 10.
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

/* Threads of one process moved from -> to. */
static int retune(pid_t pid, int fd, int from, int to)
{
    procfs_status st;
    int changed = 0;
    memset(&st, 0, sizeof st);
    st.tid = 1;
    while (devctl(fd, DCMD_PROC_TIDSTATUS, &st, sizeof st, NULL) == EOK) {
        if (st.priority == from) {
            struct sched_param sp;
            memset(&sp, 0, sizeof sp);
            sp.sched_priority = to;
            if (SchedSet(pid, st.tid, SCHED_NOCHANGE, &sp) != -1) changed++;
        }
        st.tid++;
    }
    return changed;
}

int main(int argc, char **argv)
{
    int from, to, changed = 0, matched = 0;
    DIR *proc;
    struct dirent *de;

    if (argc < 4 || parse_prio(argv[1], &from) != 0 || parse_prio(argv[2], &to) != 0) {
        fprintf(stderr, "usage: nav_boost <from 1-63> <to 1-63> <name>...\n");
        return 2;
    }
    proc = opendir("/proc");
    if (proc == NULL) {
        perror("nav_boost: /proc");
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
                && wanted(name.info.path, argv + 3, argc - 3)) {
            matched++;
            changed += retune(pid, fd, from, to);
        }
        close(fd);
    }
    closedir(proc);
    printf("%d %d\n", changed, matched);
    return 0;
}
