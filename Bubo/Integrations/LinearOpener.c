// Bubo's custom script for Linear, in Bubo's bundle (spec 16): Linear runs it on an issue with the LINEAR_*
// variables; it hands them to the Bubo of its bundle as a bubo://linear link, opening Bubo if it is closed, and exits.
// It reads no token and writes nothing: Bubo makes a Bozza, never a Sessione.
//
// Usage: bubo-linear, with LINEAR_ISSUE_IDENTIFIER and maybe LINEAR_ISSUE_BRANCH_NAME, LINEAR_WORK_DIR, LINEAR_PROMPT.
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// The longest prompt passed, in bytes: the link stays well under the arguments' limit. Bubo cuts at the same length.
#define MAXIMUM_PROMPT 100000

static const char *const parameters[][2] = {
    {"identifier", "LINEAR_ISSUE_IDENTIFIER"},
    {"branch", "LINEAR_ISSUE_BRANCH_NAME"},
    {"workdir", "LINEAR_WORK_DIR"},
    {"prompt", "LINEAR_PROMPT"},
};

// Appends the first `length` bytes of `value` to `out`, percent-encoded but for the unreserved characters.
static char *encode(char *out, const char *value, size_t length) {
    static const char hex[] = "0123456789ABCDEF";
    for (size_t i = 0; i < length; i++) {
        unsigned char c = (unsigned char)value[i];
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
            (c != '\0' && strchr("-._~", c) != NULL)) {
            *out++ = (char)c;
        } else {
            *out++ = '%';
            *out++ = hex[c >> 4];
            *out++ = hex[c & 15];
        }
    }
    return out;
}

int main(void) {
    const char *identifier = getenv("LINEAR_ISSUE_IDENTIFIER");
    if (identifier == NULL || *identifier == '\0') {
        fputs("bubo-linear: LINEAR_ISSUE_IDENTIFIER is missing; run it from Linear's custom script\n", stderr);
        return 64;
    }

    // The bundle: this executable is in Bubo.app/Contents/Helpers.
    char path[PATH_MAX], app[PATH_MAX];
    uint32_t size = sizeof path;
    if (_NSGetExecutablePath(path, &size) != 0 || realpath(path, app) == NULL) {
        perror("bubo-linear");
        return 71;
    }
    for (int level = 0; level < 3; level++) {
        char *slash = strrchr(app, '/');
        if (slash == NULL || slash == app) {
            fputs("bubo-linear: not inside Bubo.app\n", stderr);
            return 71;
        }
        *slash = '\0';
    }

    enum { count = sizeof parameters / sizeof parameters[0] };
    const char *values[count];
    size_t lengths[count], capacity = sizeof "bubo://linear";
    for (size_t i = 0; i < count; i++) {
        values[i] = getenv(parameters[i][1]);
        if (values[i] == NULL) values[i] = "";
        lengths[i] = strlen(values[i]);
        if (lengths[i] > MAXIMUM_PROMPT) {
            // Cut at the start of a UTF-8 character.
            lengths[i] = MAXIMUM_PROMPT;
            while (lengths[i] > 0 && ((unsigned char)values[i][lengths[i]] & 0xC0) == 0x80) lengths[i]--;
        }
        capacity += strlen(parameters[i][0]) + 2 + 3 * lengths[i];
    }
    char *link = malloc(capacity);
    if (link == NULL) {
        perror("bubo-linear");
        return 71;
    }
    char *out = stpcpy(link, "bubo://linear");
    for (size_t i = 0; i < count; i++) {
        *out++ = i == 0 ? '?' : '&';
        out = stpcpy(out, parameters[i][0]);
        *out++ = '=';
        out = encode(out, values[i], lengths[i]);
    }
    *out = '\0';

    // open(1) brings the link to this bundle's Bubo, launching it if needed, and returns.
    char *const arguments[] = {"open", "-a", app, link, NULL};
    execv("/usr/bin/open", arguments);
    perror("/usr/bin/open");
    return 127;
}
