#include "../OrbShading.h"

// Chat · conversazione: a brain in profile, front to the left, with two folds raised on its side, the cerebellum
// and the stem below.
static float cervello(float3 p, float) {
    p.y -= 0.08;
    float lobes = min(min(length(p.xy - float2(-0.40, 0.08)) - 0.36, length(p.xy - float2(-0.02, 0.28)) - 0.40),
                      min(length(p.xy - float2(0.38, 0.12)) - 0.36, length(p.xy - float2(-0.05, -0.14)) - 0.36));
    const float round = 0.18;
    float cerebrum = extrude(lobes + round, p.z, 0.10) - round;
    float cerebellum = extrude(length(p.xy - float2(0.40, -0.30)) - 0.10, p.z, 0.04) - 0.14;
    float stem = sdSegment(p, float3(0.14, -0.40, 0), float3(0.22, -0.74, 0), 0.09);
    float folds = min(sdSegment(p, float3(0.08, 0.52, 0.26), float3(-0.06, 0.10, 0.26), 0.045),
                      sdSegment(p, float3(-0.42, -0.08, 0.26), float3(0.30, 0.04, 0.26), 0.045));
    return min(min(cerebrum, cerebellum), min(stem, folds));
}

ORB_FORMA(cervello)
