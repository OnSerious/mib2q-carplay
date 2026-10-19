/* Host stand-in for QNX <sys/procfs.h>: only the fields nav_boost.c reads (tests/nav_boost_test.c). */
#ifndef NAV_BOOST_STUB_PROCFS_H
#define NAV_BOOST_STUB_PROCFS_H
#include <stdint.h>
#include <sys/types.h>
#define DCMD_PROC_MAPDEBUG_BASE 1
#define DCMD_PROC_INFO          2
#define DCMD_PROC_TIDSTATUS     3
typedef struct { uint64_t vaddr; uint64_t size; uint32_t flags; uint32_t dev; uint64_t offset; uint64_t ino; uint32_t reserved; char path[1]; } procfs_debuginfo;
typedef struct { pid_t pid; pid_t parent; uint64_t start_time; } procfs_info;
typedef struct { pid_t pid; int tid; uint8_t priority; uint8_t real_priority; uint64_t start_time; } procfs_status;
#endif
