/* Host stand-in for QNX <devctl.h>: just enough for navboost/nav_boost.c (tests/nav_boost_test.c). */
#ifndef NAV_BOOST_STUB_DEVCTL_H
#define NAV_BOOST_STUB_DEVCTL_H
#include <stddef.h>
#define EOK 0
int devctl(int fd, int dcmd, void *data, size_t nbytes, int *info);
#endif
