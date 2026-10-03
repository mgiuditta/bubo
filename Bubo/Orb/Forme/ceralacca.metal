#include "../OrbShading.h"

// Mail: a round wax seal with a lumpy edge, a raised ring and a boss in the middle.
static float ceralacca(float3 p, float) {
    float2 q = p.xy;
    float d = length(q) - 0.52;
    for (int i = 0; i < 9; i++) {
        float a = float(i) * 0.698 + 0.25 * sin(float(i) * 2.3);
        float r = 0.10 + 0.03 * sin(float(i) * 1.7);
        d = min(d, length(q - 0.56 * float2(cos(a), sin(a))) - r);
    }
    d = min(d, length(q - float2(0.34, -0.62)) - 0.13);
    float disc = extrude(d, p.z, 0.05) - 0.04;
    float ring = sdTorusXY(p - float3(0, 0, 0.08), 0.32, 0.05);
    float boss = length(p - float3(0, 0, 0.09)) - 0.15;
    return min(disc, min(ring, boss));
}

ORB_FORMA(ceralacca)
