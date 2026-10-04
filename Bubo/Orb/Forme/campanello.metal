#include "../OrbShading.h"

// Viaggi · alloggi: a reception bell, a dome on a plate with a button on top that gets pressed.
static float campanelloDome(float2 p, float r) {
    if (p.y >= 0.0) return max(length(p) - r, -p.y);
    return length(float2(p.x - clamp(p.x, -r, r), p.y));
}

static float campanello(float3 p, float t) {
    float yb = 0.50 - 0.10 * pulse(fract(t / 2.4), 0.12, 0.08);
    float d = extrude(min(campanelloDome(p.xy - float2(0, -0.30), 0.60),
                          sdRoundBox2(p.xy - float2(0, -0.37), float2(0.78, 0.07), 0.03)), p.z, 0.12) - 0.04;
    d = min(d, sdSegment(p, float3(0, 0.30, 0), float3(0, yb - 0.05, 0), 0.04));
    return min(d, length(p - float3(0, yb, 0)) - 0.10);
}

ORB_FORMA(campanello)
