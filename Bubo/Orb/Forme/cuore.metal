#include "../OrbShading.h"

// Salute: a plump heart, beating lub-dub about fifty times a minute.
static float cuore(float3 p, float t) {
    float phase = fract(t / 1.2 + 0.5);                // t = 0 is between beats
    float s = 1.0 + 0.07 * pulse(phase, 0.1, 0.09) + 0.045 * pulse(phase, 0.3, 0.09);
    p /= s;
    const float size = 1.32, round = 0.15;
    float2 q = (p.xy + float2(0, 0.74)) / size;
    float heart = sdHeart2(q) * size;                  // exact inside too, so it can be shrunk
    return (extrude(heart + round, p.z, 0.05) - round) * s;
}

ORB_FORMA(cuore)
