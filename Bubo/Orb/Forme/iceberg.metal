#include "../OrbShading.h"

// Codice · verifica: an iceberg, a small tip above the waterline and a far bigger mass below it.
static float iceberg(float3 p, float) {
    float2 q = p.xy - float2(0, 0.125);
    float tip = min(sdQuad2(q, float2(-0.30, 0.0), float2(-0.08, 0.50), float2(0.10, 0.30), float2(0.30, 0.0)),
                    sdQuad2(q, float2(0.10, 0.30), float2(0.20, 0.38), float2(0.34, 0.0), float2(0.22, 0.0)));
    float mass = sdQuad2(q, float2(-0.75, -0.02), float2(0.75, -0.02), float2(0.40, -0.60), float2(-0.35, -0.75));
    float d = extrude(min(tip, mass), p.z, 0.10) - 0.03;
    float water = sdSegment(p, float3(-0.95, 0.125, 0), float3(0.95, 0.125, 0), 0.03);
    return min(d, water);
}

ORB_FORMA(iceberg)
