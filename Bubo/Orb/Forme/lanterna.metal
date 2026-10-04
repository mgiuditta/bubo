#include "../OrbShading.h"

// Codice · verifica: a lantern, an arched handle over a caged glass with a flame inside; the flame flickers.
static float lanterna(float3 p, float t) {
    float handle = sdTorusXY(p - float3(0, 0.55, 0), 0.25, 0.04);
    float cap = sdCappedCone(p - float3(0, 0.4, 0), 0.07, 0.4, 0.28);
    float base = sdCylinder(p - float3(0, -0.55, 0), 0.4, 0.07);
    float tank = sdCylinder(p - float3(0, -0.43, 0), 0.12, 0.06);
    float ring = length(float2(length(p.xz) - 0.38, p.y + 0.1)) - 0.03;
    float d = min(min(handle, cap), min(min(base, tank), ring));
    const float xs[4] = { -0.38, -0.14, 0.14, 0.38 };
    for (int i = 0; i < 4; i++) {
        d = min(d, sdSegment(p, float3(xs[i], -0.5, 0), float3(xs[i], 0.35, 0), 0.035));
    }
    float sway = 0.025 * sin(t * 7.0), rise = 0.05 * sin(t * 11.0);
    float flame = sdRoundCone(p, float3(sway * 0.3, -0.3, 0), float3(sway, rise, 0), 0.13, 0.03);
    return min(d, flame);
}

ORB_FORMA(lanterna)
