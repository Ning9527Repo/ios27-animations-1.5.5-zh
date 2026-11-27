#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../NB27ClockText.h"

int main(void) {
    const char *yes[] = {"9:00", "00:00", "23:59", "19:10:30", " 19:10:30\r\n\xe5\x91\xa8\xe5\x9b\x9b 11/26", "11/26\n\t1:05\t"};
    const char *no[] = {"", "9:5", "24:00", "12:60", "12:59:60", "12:59:02:00", "on 12:30", "12:30 now", "12:30 11/26", "11/26\n"};
    for (size_t i = 0; i < sizeof(yes)/sizeof(*yes); ++i) assert(NB27ClockText(yes[i], strlen(yes[i])));
    for (size_t i = 0; i < sizeof(no)/sizeof(*no); ++i) assert(!NB27ClockText(no[i], strlen(no[i])));
    char oversized[257] = "12:30\n";
    assert(!NB27ClockText(oversized, sizeof(oversized)));
    assert(!NB27ClockText(NULL, 5));
    puts("PASS: clock label and multiline date parsing");
    return 0;
}
