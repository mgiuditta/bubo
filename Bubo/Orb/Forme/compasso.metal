#include "../OrbShading.h"

// Codice · pianificare: a drawing compass opened in a V, the hinge on top; the legs open and close a little.
static float compasso(float3 p, float t) {
    float theta = 0.27 + 0.05 * sin(t * 1.4);
    const float2 hinge = float2(0, 0.8);
    float2 foot = hinge + 1.7 * float2(sin(theta), -cos(theta));
    float3 m = float3(abs(p.x), p.y, p.z);
    float leg = sdRoundCone(m, float3(hinge, 0), float3(foot, 0), 0.07, 0.025);
    float pivot = length(p - float3(hinge, 0)) - 0.1;
    float grip = sdSegment(p, float3(hinge, 0), float3(0, 0.95, 0), 0.04);
    return min(leg, min(pivot, grip));
}

ORB_FORMA(compasso)
