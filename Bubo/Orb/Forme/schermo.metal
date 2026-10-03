#include "../OrbShading.h"

// Codice · scrittura: a desktop monitor, a frame around a recessed screen, on a short neck and a flat foot.
static float schermo(float3 p, float) {
    float2 c = p.xy - float2(0, 0.15);
    float frame = extrude(abs(sdRoundBox2(c, float2(0.74, 0.46), 0.08)) - 0.06, p.z, 0.06);
    float screen = sdRoundBox(p - float3(0, 0.15, -0.04), float3(0.70, 0.42, 0.03), 0.03);
    float neck = sdRoundBox(p - float3(0, -0.5, 0), float3(0.09, 0.17, 0.05), 0.03);
    float foot = sdRoundBox(p - float3(0, -0.7, 0), float3(0.36, 0.05, 0.18), 0.04);
    return min(min(frame, screen), min(neck, foot));
}

ORB_FORMA(schermo)
