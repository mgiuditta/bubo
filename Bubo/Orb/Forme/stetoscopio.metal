#include "../OrbShading.h"

// Salute · visite: a stethoscope, two earpieces up top, tubes in a U joining into one, a round chest piece below.
static float stetoscopio(float3 p, float) {
    float3 q = float3(abs(p.x), p.y, p.z);
    float d = length(q - float3(0.35, 0.80, 0)) - 0.08;
    d = min(d, sdSegment(q, float3(0.35, 0.80, 0), float3(0.40, 0.30, 0), 0.05));
    d = min(d, sdSegment(q, float3(0.40, 0.30, 0), float3(0.25, -0.10, 0), 0.05));
    d = min(d, sdSegment(q, float3(0.25, -0.10, 0), float3(0, -0.20, 0), 0.05));
    d = min(d, sdSegment(p, float3(0, -0.20, 0), float3(0, -0.50, 0), 0.05));
    float chest = extrude(length(p.xy - float2(0, -0.68)) - 0.14, p.z, 0.05) - 0.06;
    float ring = sdTorusXY(p - float3(0, -0.68, 0.11), 0.14, 0.025);
    return min(d, min(chest, ring));
}

ORB_FORMA(stetoscopio)
