#include "../OrbShading.h"

// Salute · corpo: a vertical double helix, nine rungs between two strands of beads; it turns on its axis.
static float dna(float3 p, float t) {
    float d = 9.0;
    float3 prevA = float3(0), prevB = float3(0);
    for (int i = 0; i < 9; i++) {
        float y = -0.8 + 0.2 * float(i);
        float a = y * 5.0 + t * 0.8;
        float3 sa = float3(0.38 * cos(a), y, 0.38 * sin(a));
        float3 sb = float3(-sa.x, y, -sa.z);
        d = min(d, min(length(p - sa), length(p - sb)) - 0.09);
        d = min(d, sdSegment(p, sa, sb, 0.035));
        if (i > 0) {
            d = min(d, min(sdSegment(p, prevA, sa, 0.045), sdSegment(p, prevB, sb, 0.045)));
        }
        prevA = sa;
        prevB = sb;
    }
    return d;
}

ORB_FORMA(dna)
