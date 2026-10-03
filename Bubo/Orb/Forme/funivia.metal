#include "../OrbShading.h"

// Viaggi · in quota: a gondola hanging from a sloping cable and gliding along it, back and forth.
static float funivia(float3 p, float t) {
    float cable = sdSegment(p, float3(-1.0, 0.52, 0), float3(1.0, 0.82, 0), 0.03);
    float x = 0.5 * sin(t * 0.5);
    float cy = 0.67 + 0.15 * x;
    float carriage = sdRoundBox(p - float3(x, cy, 0), float3(0.07, 0.06, 0.05), 0.02);
    float hanger = sdSegment(p, float3(x, cy, 0), float3(x, cy - 0.35, 0), 0.03);
    float2 q = p.xy - float2(x, cy - 0.6);
    float cabin = extrude(sdRoundBox2(q, float2(0.36, 0.24), 0.1), p.z, 0.14) - 0.03;
    float roof = sdSegment(p, float3(x - 0.3, cy - 0.34, 0), float3(x + 0.3, cy - 0.34, 0), 0.05);
    float bars = min(sdSegment(p, float3(x - 0.12, cy - 0.78, 0.18), float3(x - 0.12, cy - 0.42, 0.18), 0.025),
                     sdSegment(p, float3(x + 0.12, cy - 0.78, 0.18), float3(x + 0.12, cy - 0.42, 0.18), 0.025));
    return min(min(cable, carriage), min(min(hanger, cabin), min(roof, bars)));
}

ORB_FORMA(funivia)
