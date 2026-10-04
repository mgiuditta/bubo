#include "../OrbShading.h"

// Codice · fork: a fork standing straight, four tines on a crossbar and a handle that widens at the end.
static float forchetta(float3 p, float) {
    float handle = sdRoundCone(p, float3(0, -0.80, 0), float3(0, -0.15, 0), 0.10, 0.06);
    float bar = sdRoundBox(p - float3(0, 0.0, 0), float3(0.30, 0.09, 0.05), 0.04);
    float3 q = float3(abs(p.x), p.y, p.z);
    float tines = min(sdSegment(q, float3(0.09, 0.05, 0), float3(0.09, 0.80, 0), 0.045),
                      sdSegment(q, float3(0.27, 0.05, 0), float3(0.27, 0.80, 0), 0.045));
    return min(min(handle, bar), tines);
}

ORB_FORMA(forchetta)
