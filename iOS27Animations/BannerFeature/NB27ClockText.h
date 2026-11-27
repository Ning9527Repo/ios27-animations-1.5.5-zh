#pragma once
#include <stdbool.h>
#include <stddef.h>

static inline bool NB27ClockDigit(char c) { return c >= '0' && c <= '9'; }
static inline bool NB27ClockSpace(char c) { return c == ' ' || c == '\t'; }
static inline bool NB27ClockLine(const char *p, size_t n) {
    if (n < 4 || n > 8 || !NB27ClockDigit(p[0])) return false;
    unsigned hour = (unsigned)(p[0] - '0');
    size_t i = 1;
    if (NB27ClockDigit(p[i])) hour = hour * 10 + (unsigned)(p[i++] - '0');
    if (hour > 23 || i + 3 > n || p[i] != ':' || p[i+1] < '0' || p[i+1] > '5' ||
        !NB27ClockDigit(p[i+2])) return false;
    i += 3;
    return i == n || (i + 3 == n && p[i] == ':' && p[i+1] >= '0' && p[i+1] <= '5' && NB27ClockDigit(p[i+2]));
}
/* Only a full clock line matches; a supplementary weekday/date line is allowed. */
static inline bool NB27ClockText(const char *p, size_t n) {
    if (!p || !n || n > 256) return false;
    for (size_t start = 0, end = 0; end <= n; ++end) {
        if (end != n && p[end] != '\n' && p[end] != '\r') continue;
        size_t a = start, b = end;
        while (a < b && NB27ClockSpace(p[a])) ++a;
        while (b > a && NB27ClockSpace(p[b-1])) --b;
        if (NB27ClockLine(p + a, b - a)) return true;
        start = end + 1;
    }
    return false;
}
