#include "../OrbShading.h"

// Codice · verifica: a radar dish on a pedestal with its feed horn; the dish turns slowly about the vertical.
static float radar(float3 p, float t) {
    float3 q = p - float3(0, 0.2, 0);
    q.xz = q.xz * rot(-t * 0.6);
    q.xy = q.xy * rot(-0.6);
    float dish = sdCappedCone(q.yxz, 0.18, 0.12, 0.55);
    float feed = sdSegment(q, float3(0.1, 0, 0), float3(0.55, 0, 0), 0.03);
    float horn = length(q - float3(0.62, 0, 0)) - 0.07;
    float stem = sdSegment(p, float3(0, -0.05, 0), float3(0, -0.6, 0), 0.08);
    float base = sdCylinder(p - float3(0, -0.7, 0), 0.4, 0.07);
    return min(min(dish, feed), min(horn, min(stem, base)));
}

ORB_FORMA(radar)
