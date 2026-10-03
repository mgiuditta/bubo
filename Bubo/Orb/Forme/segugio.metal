#include "../OrbShading.h"

// Ricerca · indagine: a hound in profile facing right, nose to the ground, a long ear, four legs and a raised tail;
// it sniffs along, legs stepping, nose bobbing.
static float segugio(float3 p, float t) {
    float bob = 0.04 * sin(t * 6.0);
    float body = sdRoundCone(p, float3(-0.50, 0.05, 0), float3(0.15, 0.05, 0), 0.20, 0.24);
    float neck = sdSegment(p, float3(0.20, 0.15, 0), float3(0.45, -0.05, 0), 0.14);
    float head = sdRoundCone(p, float3(0.45, -0.05, 0), float3(0.80, -0.30 + bob, 0), 0.17, 0.08);
    float nose = length(p - float3(0.86, -0.33 + bob, 0)) - 0.07;
    float ear = sdRoundCone(p, float3(0.38, 0.02, 0.12), float3(0.35, -0.35, 0.14), 0.10, 0.06);
    float tail = sdSegment(p, float3(-0.62, 0.12, 0), float3(-0.85, 0.45, 0), 0.05);
    float d = min(min(body, neck), min(min(head, nose), min(ear, tail)));
    const float legX[4] = { -0.45, -0.28, 0.05, 0.20 };
    for (int i = 0; i < 4; i++) {
        float stride = 0.07 * sin(t * 5.0 + ((i == 0 || i == 3) ? 0.0 : 3.1415927));
        d = min(d, sdSegment(p, float3(legX[i], -0.10, 0), float3(legX[i] + stride, -0.62, 0), 0.07));
    }
    return d;
}

ORB_FORMA(segugio)
