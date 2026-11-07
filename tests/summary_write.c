/* SPDX-License-Identifier: Apache-2.0 */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stddef.h>
#include <unistd.h>
static int64_t mode, calls;
ssize_t __real_write(int, const void *, size_t);
int __real_pthread_sigmask(int, const sigset_t *, sigset_t *);
void gc_summary_mode(int64_t value) { mode = value; calls = 0; }
int64_t gc_summary_calls(void) { return calls; }
ssize_t __wrap_write(int fd, const void *data, size_t size) {
    if (fd != STDERR_FILENO) return __real_write(fd, data, size);
    calls++;
    if ((mode == 1 && calls == 1) || mode == 3) { errno = EINTR; return -1; }
    if (mode == 2 && calls > 1) { errno = EAGAIN; return -1; }
    return __real_write(fd, data, size < 3 ? size : 3);
}
int __wrap_pthread_sigmask(int how, const sigset_t *set, sigset_t *old) {
    if (mode == 4 && how == SIG_SETMASK) return EINVAL;
    return __real_pthread_sigmask(how, set, old);
}
