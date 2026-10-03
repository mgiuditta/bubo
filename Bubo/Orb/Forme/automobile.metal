#include "../OrbShading.h"

// Viaggi: a car in profile, front to the right: body, cabin and four wheels (two on each side).
static float automobile(float3 p, float) {
    float body = sdRoundBox2(p.xy - float2(0, -0.15), float2(0.85, 0.18), 0.12);
    float cabin = sdQuad2(p.xy, float2(-0.45, 0.02), float2(0.42, 0.02), float2(0.20, 0.42), float2(-0.30, 0.42));
    float d = extrude(min(body, cabin), p.z, 0.18) - 0.04;
    for (int i = 0; i < 2; i++) {
        float x = i == 0 ? -0.50 : 0.50;
        d = min(d, sdCylinder(float3(p.x - x, abs(p.z) - 0.20, p.y + 0.33), 0.22, 0.06));
    }
    return d;
}

ORB_FORMA(automobile)
