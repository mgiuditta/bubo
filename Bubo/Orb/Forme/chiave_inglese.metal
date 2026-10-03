#include "../OrbShading.h"

// Codice · rilascio: an open-end wrench set on the diagonal, rocking as if it were tightening.
static float chiave_inglese(float3 p, float t) {
    float2 xy = p.xy * rot(-0.6 - 0.25 * sin(t * 2.2));
    float handle = udSegment2(xy, float2(0, -0.65), float2(0, 0.30)) - 0.11;
    float jaw = min(sdRoundBox2(float2(abs(xy.x), xy.y) - float2(0.20, 0.55), float2(0.10, 0.25), 0.03),
                    sdRoundBox2(xy - float2(0, 0.38), float2(0.30, 0.10), 0.03));
    return extrude(min(handle, jaw), p.z, 0.08) - 0.03;
}

ORB_FORMA(chiave_inglese)
