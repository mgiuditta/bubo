#include "../OrbShading.h"

// Musica: a hand drum seen from a little above, two drumsticks crossed over its skin and beating it in turn.
static float tamburo(float3 p, float t) {
    float3 q = p;
    q.yz = p.yz * rot(-0.45);                          // tipped toward the camera
    float body = sdCylinder(q - float3(0, -0.15, 0), 0.55, 0.28);
    float rimTop = sdCylinder(q - float3(0, 0.14, 0), 0.59, 0.04);
    float rimBottom = sdCylinder(q - float3(0, -0.44, 0), 0.59, 0.04);
    float d = min(body, min(rimTop, rimBottom));
    for (int i = 0; i < 5; i++) {                      // tension rods on the front
        float a = 0.5 + 0.54 * float(i);
        float2 xz = 0.585 * float2(cos(a), sin(a));
        d = min(d, sdSegment(q, float3(xz.x, -0.40, xz.y), float3(xz.x, 0.10, xz.y), 0.03));
    }
    float lift = 0.5 - 0.5 * cos(t * 6.0);             // t = 0: one stick down, one up
    float3 aEnd = float3(0.6, 0.15 + 0.15 * lift, 0.15), bEnd = float3(-0.6, 0.15 + 0.15 * (1.0 - lift), 0.15);
    float sticks = min(sdSegment(p, float3(-0.6, 0.8, 0.15), aEnd, 0.05), sdSegment(p, float3(0.6, 0.8, 0.15), bEnd, 0.05));
    return min(d, sticks);
}

ORB_FORMA(tamburo)
