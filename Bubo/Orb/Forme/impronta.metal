#include "../OrbShading.h"

// Codice · accesso: a fingerprint, concentric oval ridges around a short core.
static float impronta(float3 p, float) {
    float line = udSegment2(p.xy, float2(0, -0.18), float2(0, 0.18));
    float d = udSegment2(p.xy, float2(0, -0.10), float2(0, 0.10)) - 0.06;
    for (int i = 0; i < 3; i++) d = min(d, abs(line - (0.26 + 0.20 * float(i))) - 0.025);
    return extrude(d, p.z, 0.03) - 0.025;
}

ORB_FORMA(impronta)
