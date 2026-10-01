// The launcher of the terminal's shell, in Bubo's bundle: posix_spawn cannot give the shell a
// controlling terminal, so Bubo starts this with the disclaim and it does the rest (spec 15, measure B).
//
// Usage: bubo-terminal <shell> <argv0> [arguments...], with the terminal on 0, 1 and 2.
#include <stdio.h>
#include <sys/ioctl.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    if (argc < 3) {
        fputs("usage: bubo-terminal shell argv0 [arguments...]\n", stderr);
        return 64;
    }
    // A new session, whose controlling terminal is the one on standard input: ⌃C and job control work.
    if (setsid() < 0 || ioctl(STDIN_FILENO, TIOCSCTTY, 0) < 0) {
        perror("bubo-terminal");
        return 71;
    }
    execv(argv[1], &argv[2]);
    perror(argv[1]);
    return 127;
}
