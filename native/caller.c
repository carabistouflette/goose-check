/* SPDX-License-Identifier: Apache-2.0 */
/* Adapted from Honk453aa53 native/platform.c. See THIRD_PARTY.md and NOTICE. */
#define _GNU_SOURCE
#include <errno.h>
#include <limits.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
// Application-owned cancellation guard. Handlers never use child identities.
static volatile sig_atomic_t pending_signals = 0;
static volatile sig_atomic_t interrupted = 0;
static struct {
  struct sigaction old_int, old_term, old_chld;
  sigset_t mask, blocked;
  bool active;
} process_guard;
static void latch_signal(int number, siginfo_t *info, void *context) {
  (void)context;
  int saved = errno;
  interrupted = number;
  pending_signals |= number == SIGTERM ? 4 :
      (info && info->si_code == SI_KERNEL ? 2 : 1);
  errno = saved;
}
bool gc_guard_begin(void) {
  if (process_guard.active) return false;
  sigemptyset(&process_guard.blocked);
  sigaddset(&process_guard.blocked, SIGINT);
  sigaddset(&process_guard.blocked, SIGTERM);
  sigaddset(&process_guard.blocked, SIGCHLD);
  if (sigprocmask(SIG_BLOCK, &process_guard.blocked, &process_guard.mask) < 0)
    return false;
  if (sigaction(SIGINT, NULL, &process_guard.old_int) < 0 ||
      sigaction(SIGTERM, NULL, &process_guard.old_term) < 0 ||
      sigaction(SIGCHLD, NULL, &process_guard.old_chld) < 0) goto mask_failure;
  struct sigaction action;
  memset(&action, 0, sizeof action);
  action.sa_mask = process_guard.blocked;
  action.sa_handler = SIG_DFL;
  if (sigaction(SIGCHLD, &action, NULL) < 0) goto mask_failure;
  action.sa_sigaction = latch_signal;
  action.sa_flags = SA_SIGINFO;
  if (sigaction(SIGINT, &action, NULL) < 0) goto child_failure;
  if (sigaction(SIGTERM, &action, NULL) < 0) goto int_failure;
  pending_signals = 0;
  interrupted = 0;
  process_guard.active = true;
  if (sigprocmask(SIG_SETMASK, &process_guard.mask, NULL) == 0) return true;
  process_guard.active = false;
  sigaction(SIGTERM, &process_guard.old_term, NULL);
int_failure:
  sigaction(SIGINT, &process_guard.old_int, NULL);
child_failure:
  sigaction(SIGCHLD, &process_guard.old_chld, NULL);
mask_failure:
  sigprocmask(SIG_SETMASK, &process_guard.mask, NULL);
  return false;
}
int64_t gc_guard_take(int64_t child) {
  sigset_t previous;
  if (!process_guard.active ||
      sigprocmask(SIG_BLOCK, &process_guard.blocked, &previous) < 0) return -1;
  int pending = pending_signals;
  pending_signals = 0;
  // Positive id is queried immediately before this call, with no external
  // reaper or intervening Child operation. An exited child is still reserved.
  if ((pending & 2) && child > 0 && child <= INT_MAX &&
      getpgid((pid_t)child) == getpgrp()) pending &= ~2;
  if (sigprocmask(SIG_SETMASK, &previous, NULL) < 0) return -1;
  return pending;
}
int64_t gc_guard_end(void) {
  if (!process_guard.active ||
      sigprocmask(SIG_BLOCK, &process_guard.blocked, NULL) < 0) return -1;
  int received = interrupted;
  bool ok = sigaction(SIGINT, &process_guard.old_int, NULL) == 0;
  ok = sigaction(SIGTERM, &process_guard.old_term, NULL) == 0 && ok;
  ok = sigaction(SIGCHLD, &process_guard.old_chld, NULL) == 0 && ok;
  ok = sigprocmask(SIG_SETMASK, &process_guard.mask, NULL) == 0 && ok;
  if (ok) process_guard.active = false;
  return ok ? received : -1;
}
void gc_recover(int64_t transferred) {
  // A library Status transferred this reserved PID exactly once. Only this
  // recovery owner may reap/signal it; Child no longer owns it.
  if (transferred <= 0 || transferred > INT_MAX) abort();
  pid_t pid = (pid_t)transferred;
  int status;
  bool diagnosed = false, signalled = false;
  for (;;) {
    pid_t result = waitpid(pid, &status, WNOHANG);
    if (result == pid && (WIFEXITED(status) || WIFSIGNALED(status))) return;
    if (result < 0 && errno == ECHILD) return;
    if (result < 0 && errno == EINTR) continue;
    if (result == 0 && !signalled) {
      // Reservation remains held; no normal Child operation follows transfer.
      int sent;
      do { sent = kill(pid, SIGKILL); } while (sent < 0 && errno == EINTR);
      signalled = true;
    }
    if (!diagnosed) {
      fputs("goose-check: recovering transferred child before returning\n", stderr);
      diagnosed = true;
    }
    // Permission-denied waits/signals must not release locks or spin. A child
    // that cannot be signalled may need to terminate naturally.
    struct timespec pause = {0, 20000000};
    while (nanosleep(&pause, &pause) < 0 && errno == EINTR) {}
  }
}
