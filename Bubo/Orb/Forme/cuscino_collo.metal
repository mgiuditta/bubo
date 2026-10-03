#include "../OrbShading.h"

// Viaggi: a U-shaped travel pillow, a thick tube bent into a half ring with its two ends reaching up.
static float cuscino_collo(float3 p, float) {
    const float R = 0.62, r = 0.22;
    float3 q = float3(abs(p.x), p.y, p.z);
    float bend = p.y < 0.0 ? length(float2(length(p.xy) - R, p.z)) - r : length(p - float3(p.x < 0.0 ? -R : R, 0, 0)) - r;
    float arm = sdSegment(q, float3(R, 0, 0), float3(R, 0.45, 0), r);
    return min(bend, arm);
}

ORB_FORMA(cuscino_collo)
