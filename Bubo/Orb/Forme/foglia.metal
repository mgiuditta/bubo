#include "../OrbShading.h"

// Tempo: a maple leaf with its stalk, falling the way a leaf does: swaying and turning.
static float foglia(float3 p, float t) {
    p.x -= 0.12 * sin(t * 1.5);
    p.xy = p.xy * rot(-0.4 * sin(t * 1.5));
    float leaf = extrude(sdStar5(p.xy - float2(0, 0.10), 0.60, 0.60), p.z, 0.03) - 0.03;
    float stalk = sdSegment(p, float3(0, -0.20, 0), float3(0, -0.75, 0), 0.04);
    return min(leaf, stalk);
}

ORB_FORMA(foglia)
