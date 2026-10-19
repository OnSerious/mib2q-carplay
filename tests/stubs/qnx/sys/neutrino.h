/* Host stand-in for QNX <sys/neutrino.h> (tests/nav_boost_test.c). */
#ifndef NAV_BOOST_STUB_NEUTRINO_H
#define NAV_BOOST_STUB_NEUTRINO_H
#include <sched.h>
#include <sys/types.h>
#define SCHED_NOCHANGE 0
int SchedSet(pid_t pid, int tid, int policy, const struct sched_param *param);
#endif
