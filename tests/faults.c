/* SPDX-License-Identifier: Apache-2.0 */
/* Linked only into a content-fingerprinted test binary, never production. */
#define _GNU_SOURCE
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static pid_t owned_pid;
static int owned_fd = -1, denied_waits;
static bool clock_failed, recovering, terminal;
static bool mode(const char *value) {
    const char *actual = getenv("GOOSE_CHECK_FAULT");
    return actual && !strcmp(actual, value);
}
static void event(const char *value) {
    const char *path = getenv("GOOSE_CHECK_TRACE");
    assert(path);
    int fd = open(path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0600);
    assert(fd >= 0);
    size_t size = strlen(value);
    assert(write(fd, value, size) == (ssize_t)size && close(fd) == 0);
}
static void guarded(void) {
    struct sigaction action;
    assert(sigaction(SIGCHLD, NULL, &action) == 0);
    assert(action.sa_handler == SIG_DFL && !(action.sa_flags & SA_NOCLDWAIT));
    assert(sigaction(SIGTERM, NULL, &action) == 0 && (action.sa_flags & SA_SIGINFO));
}
bool __real_gc_guard_begin(void);
bool __wrap_gc_guard_begin(void) {
    bool result = __real_gc_guard_begin();
    if (result && mode("prestart")) {
        event("prestart\n"); assert(raise(SIGTERM) == 0);
    }
    return result;
}
void __real_gc_recover(int64_t pid);
void __wrap_gc_recover(int64_t pid) {
    assert(mode("transfer") && pid == owned_pid && !recovering && !terminal);
    guarded(); event("recover_begin\n"); recovering = true;
    __real_gc_recover(pid);
    assert(terminal && denied_waits == 2);
    guarded(); event("recover_end\n");
}
int __real_clock_gettime(clockid_t clock, struct timespec *value);
int __wrap_clock_gettime(clockid_t clock, struct timespec *value) {
    if (clock == CLOCK_MONOTONIC && mode("transfer") && owned_pid > 0 && !clock_failed) {
        clock_failed = true; event("clock_failure\n"); errno = EIO; return -1;
    }
    return __real_clock_gettime(clock, value);
}
long __real_syscall(long number, ...);
long __wrap_syscall(long number, ...) {
    va_list args; va_start(args, number);
    long result;
    if (number == SYS_pidfd_open) {
        int pid = va_arg(args, int), flags = va_arg(args, int);
        result = __real_syscall(number, pid, flags);
        if (mode("transfer") && result >= 0) {
            assert(owned_pid == 0); owned_pid = pid; owned_fd = (int)result;
            event("registered\n");
        }
    } else if (number == SYS_pidfd_send_signal) {
        int fd = va_arg(args, int), sig = va_arg(args, int);
        void *info = va_arg(args, void *); int flags = va_arg(args, int);
        assert(!terminal || fd != owned_fd);
        if (mode("transfer") && fd == owned_fd && !recovering) {
            assert(sig == SIGKILL); event("deny_pidfd\n"); errno = EPERM; result = -1;
        } else result = __real_syscall(number, fd, sig, info, flags);
    } else {
        assert(number == SYS_openat2);
        int directory = va_arg(args, int);
        const char *path = va_arg(args, const char *);
        const void *how = va_arg(args, const void *); size_t size = va_arg(args, size_t);
        result = __real_syscall(number, directory, path, how, size);
    }
    va_end(args); return result;
}
int __real_kill(pid_t pid, int sig);
int __wrap_kill(pid_t pid, int sig) {
    assert(!terminal || pid != owned_pid);
    if (mode("transfer") && pid == owned_pid) {
        assert(sig == SIGKILL);
        if (!recovering) { event("deny_numeric\n"); errno = EPERM; return -1; }
        guarded(); event("kill_owned\n");
    }
    return __real_kill(pid, sig);
}
pid_t __real_waitpid(pid_t pid, int *status, int options);
pid_t __wrap_waitpid(pid_t pid, int *status, int options) {
    if (recovering && pid == owned_pid && denied_waits < 2) {
        guarded(); ++denied_waits; event("deny_recovery_wait\n"); errno = EPERM; return -1;
    }
    pid_t result = __real_waitpid(pid, status, options);
    if (recovering && pid == owned_pid && result == pid &&
        (WIFEXITED(*status) || WIFSIGNALED(*status))) {
        assert(!terminal); terminal = true; event("terminal\n");
    }
    return result;
}
