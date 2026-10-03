#include "../OrbShading.h"

// Finanza: a bull in profile facing right, with a shoulder hump, forward-pointing horns, four legs and a tail.
static float toro(float3 p, float) {
    float d = sdSegment(p, float3(-0.50, 0.08, 0), float3(0.12, 0.08, 0), 0.33);
    d = min(d, length(p - float3(0.0, 0.36, 0)) - 0.30);
    d = min(d, sdRoundCone(p, float3(0.45, 0.14, 0), float3(0.78, -0.06, 0), 0.23, 0.13));
    d = min(d, sdSegment(p, float3(0.50, 0.32, 0), float3(0.62, 0.56, 0), 0.045));
    d = min(d, sdSegment(p, float3(0.62, 0.56, 0), float3(0.86, 0.62, 0), 0.045));
    const float legs[4] = { -0.50, -0.30, 0.05, 0.25 };
    for (int i = 0; i < 4; i++) {
        d = min(d, sdSegment(p, float3(legs[i], -0.10, 0), float3(legs[i], -0.72, 0), 0.075));
    }
    return min(d, sdSegment(p, float3(-0.80, 0.20, 0), float3(-0.95, -0.25, 0), 0.035));
}

ORB_FORMA(toro)
