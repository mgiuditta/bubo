#include "../OrbShading.h"

// Codice: an elbow pipe with a flange at each end.
static float tubatura(float3 p, float) {
    p.xy += float2(-0.10, 0.13);
    float d = sdSegment(p, float3(-0.70, -0.30, 0), float3(0.30, -0.30, 0), 0.17);
    d = min(d, sdSegment(p, float3(0.30, -0.30, 0), float3(0.30, 0.70, 0), 0.17));
    d = min(d, sdRoundBox(p - float3(-0.72, -0.30, 0), float3(0.06, 0.27, 0.27), 0.02));
    d = min(d, sdRoundBox(p - float3(0.30, 0.72, 0), float3(0.27, 0.06, 0.27), 0.02));
    return d;
}

ORB_FORMA(tubatura)
