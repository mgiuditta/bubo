#include "../OrbShading.h"

// Finanza: a gold ingot, a truncated pyramid, seen with its top face tilted toward the viewer.
static float lingotto(float3 p, float) {
    p.yz = p.yz * rot(-0.4);
    float bar = extrude(sdQuad2(p.xy, float2(-0.80, -0.30), float2(0.80, -0.30), float2(0.58, 0.30), float2(-0.58, 0.30)), p.z, 0.28) - 0.04;
    float top = sdRoundBox(p - float3(0, 0.33, 0), float3(0.46, 0.03, 0.20), 0.02);
    return min(bar, top);
}

ORB_FORMA(lingotto)
