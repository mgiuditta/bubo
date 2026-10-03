#include "../OrbShading.h"

// Salute · movimento: a football with its twelve pentagon patches raised, bouncing over a floor disc and turning as it goes.
static float pallone(float3 p, float t) {
    float height = -0.35 + 0.5 * abs(sin(t * 2.4));
    float3 q = p - float3(0, height, 0);
    q.xy = q.xy * rot(t * 1.5);
    float d = length(q) - 0.42;
    const float3 v[6] = { float3(0, 0.5257, 0.8507), float3(0, 0.5257, -0.8507), float3(0.5257, 0.8507, 0),
                          float3(-0.5257, 0.8507, 0), float3(0.8507, 0, 0.5257), float3(0.8507, 0, -0.5257) };
    for (int i = 0; i < 6; i++) {
        d = min(d, min(length(q - v[i] * 0.40), length(q + v[i] * 0.40)) - 0.12);
    }
    float floorDisc = sdCylinder(p - float3(0, -0.93, 0), 0.4, 0.015) - 0.02;
    return min(d, floorDisc);
}

ORB_FORMA(pallone)
