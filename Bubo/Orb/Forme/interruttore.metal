#include "../OrbShading.h"

// Codice: a toggle switch on its side, a slim track and a round knob that snaps from one end to the other.
static float interruttore(float3 p, float t) {
    float x = 0.4 * clamp(3.0 * sin(t * 1.3 + 1.0), -1.0, 1.0);
    float track = sdSegment(p, float3(-0.5, 0, 0), float3(0.5, 0, 0), 0.2);
    float knob = length(p - float3(x, 0, 0.05)) - 0.33;
    return min(track, knob);
}

ORB_FORMA(interruttore)
