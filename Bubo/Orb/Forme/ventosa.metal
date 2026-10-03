#include "../OrbShading.h"

// Codice: a sink plunger, a straight handle on a rubber cup; the cup is pressed flat and lifts again.
static float ventosa(float3 p, float t) {
    p.y += 0.17;
    float w = 0.5 - 0.5 * cos(t * 2.2);                  // 0 at rest, 1 pressed
    float h = 0.20 - 0.07 * w;
    float top = -0.62 + 2.0 * h;
    float cup = sdCappedCone(p - float3(0, -0.62 + h, 0), h, 0.46, 0.10);
    float handle = sdSegment(p, float3(0, top - 0.05, 0), float3(0, 0.80, 0), 0.055);
    float knob = length(p - float3(0, 0.88, 0)) - 0.09;
    return min(cup, min(handle, knob));
}

ORB_FORMA(ventosa)
