#include "../OrbShading.h"

// Codice · infrastruttura: an electric plug, two prongs up, a strain relief and a length of cable.
static float spina(float3 p, float) {
    float body = sdRoundBox(p - float3(0, -0.10, 0), float3(0.40, 0.30, 0.20), 0.10);
    float3 q = float3(abs(p.x), p.y, p.z);
    float prong = sdRoundBox(q - float3(0.20, 0.45, 0), float3(0.06, 0.30, 0.03), 0.02);
    float relief = sdRoundCone(p, float3(0, -0.36, 0), float3(0, -0.62, 0), 0.20, 0.10);
    float cable = sdSegment(p, float3(0, -0.60, 0), float3(0, -0.85, 0), 0.08);
    return min(min(body, prong), min(relief, cable));
}

ORB_FORMA(spina)
