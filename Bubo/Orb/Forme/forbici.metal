#include "../OrbShading.h"

// One half of the scissors, pointing up: blade, shank and finger ring around the pivot at the origin.
static float forbiciHalf(float3 p) {
    float blade = sdRoundCone(p, float3(0, 0, 0), float3(0, 0.80, 0), 0.075, 0.02);
    float shank = sdSegment(p, float3(0, 0, 0), float3(0, -0.42, 0), 0.05);
    float ring = sdTorusXY(p - float3(0, -0.60, 0), 0.17, 0.05);
    return min(blade, min(shank, ring));
}

// Codice · rimozione: open scissors in an X with a ring on each handle; the blades close and reopen slowly.
static float forbici(float3 p, float t) {
    float a = 0.2 + 0.12 * sin(t * 1.2);
    float3 u = float3(p.xy * rot(a), p.z), v = float3(p.xy * rot(-a), p.z);
    float screw = length(p - float3(0, 0, 0.07)) - 0.06;
    return min(min(forbiciHalf(u), forbiciHalf(v)), screw);
}

ORB_FORMA(forbici)
