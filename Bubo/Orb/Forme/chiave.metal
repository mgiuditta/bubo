#include "../OrbShading.h"

// Codice · segreti: an old key standing upright, a round bow with a real hole and two teeth.
static float chiave(float3 p, float) {
    float bow = sdTorusXY(p - float3(0, 0.62, 0), 0.25, 0.08);
    float shaft = sdSegment(p, float3(0, 0.37, 0), float3(0, -0.85, 0), 0.07);
    float collar = length(p - float3(0, 0.3, 0)) - 0.11;
    float teeth = min(sdRoundBox(p - float3(0.14, -0.6, 0), float3(0.1, 0.06, 0.05), 0.02),
                      sdRoundBox(p - float3(0.14, -0.8, 0), float3(0.1, 0.06, 0.05), 0.02));
    return min(min(bow, shaft), min(collar, teeth));
}

ORB_FORMA(chiave)
