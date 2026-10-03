#include "../OrbShading.h"

// Chat · insetti e piccoli animali: a butterfly seen from above, four wings opened wide that beat together.
static float farfalla(float3 p, float t) {
    float body = sdSegment(p, float3(0, -0.4, 0), float3(0, 0.3, 0), 0.06);
    float head = length(p - float3(0, 0.4, 0)) - 0.09;
    float3 m = float3(abs(p.x), p.y, p.z);
    float feeler = sdSegment(m, float3(0.03, 0.46, 0), float3(0.2, 0.74, 0), 0.03);
    float3 w = m;
    w.xz = w.xz * rot(0.45 * sin(t * 5.0)); // the wings fold up and down around the body
    float upper = udSegment2(w.xy, float2(0.08, 0.15), float2(0.6, 0.52)) - 0.27;
    float lower = udSegment2(w.xy, float2(0.08, -0.12), float2(0.36, -0.58)) - 0.19;
    float wings = extrude(min(upper, lower), w.z, 0.02) - 0.02;
    return min(min(body, head), min(feeler, wings));
}

ORB_FORMA(farfalla)
