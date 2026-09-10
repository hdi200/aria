#include "fluidsynth_priv.h"
#include <stdio.h>
static int check(int groups, int effects) {
    FLUID_DECLARE_VLA(void *, buffers, groups * 2 + effects * 2);
    for (int i = 0; i < groups * 2 + effects * 2; ++i) buffers[i] = &groups;
    for (int i = 0; i < groups * 2 + effects * 2; ++i) if (buffers[i] != &groups) return 1;
    return 0;
}
int main(void) {
    for (int groups = 1; groups <= 128; ++groups) if (check(groups, 2)) return 1;
    puts("PASS: composite pointer counts for all 128 mixer output groups");
    return 0;
}
