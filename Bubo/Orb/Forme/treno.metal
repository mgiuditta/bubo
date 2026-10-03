#include "../OrbShading.h"

// Viaggi: a steam locomotive seen three-quarters: boiler, cab, chimney, chassis and wheels.
static float treno(float3 p, float) {
    p.xz = p.xz * rot(-0.6);
    const float s = 0.85;
    p /= s;
    float boiler = sdSegment(p, float3(-0.25, 0.08, 0), float3(0.78, 0.08, 0), 0.32);
    float cab = sdRoundBox(p - float3(-0.55, 0.12, 0), float3(0.25, 0.45, 0.32), 0.03);
    float roof = sdRoundBox(p - float3(-0.55, 0.60, 0), float3(0.33, 0.05, 0.38), 0.02);
    float chimney = sdCylinder(p - float3(0.55, 0.45, 0), 0.08, 0.14);
    float flare = sdCappedCone(p - float3(0.55, 0.65, 0), 0.07, 0.08, 0.15);
    float chassis = sdRoundBox(p - float3(0.05, -0.22, 0), float3(0.90, 0.07, 0.28), 0.03);
    float side = abs(p.z) - 0.30;
    float wheels = 9.0;
    for (int i = 0; i < 3; i++) {
        wheels = min(wheels, sdCylinder(float3(p.x - (-0.45 + 0.40 * float(i)), side, p.y + 0.36), 0.20, 0.05));
    }
    return min(min(min(boiler, cab), min(roof, chimney)), min(min(flare, chassis), wheels)) * s;
}

ORB_FORMA(treno)
