#include "../OrbShading.h"

// Viaggi · orientamento: a round compass with a bezel, four marks and a diamond needle that swings.
static float bussola(float3 p, float t) {
    float body = extrude(length(p.xy) - 0.50, p.z, 0.08) - 0.10;
    float bezel = sdTorusXY(p - float3(0, 0, 0.12), 0.56, 0.04);
    float2 l = p.xy * rot(0.4 * sin(t * 1.3));
    float needle = extrude(sdQuad2(l, float2(0, 0.38), float2(0.09, 0), float2(0, -0.38), float2(-0.09, 0)), p.z - 0.13, 0.025) - 0.01;
    float hub = length(p - float3(0, 0, 0.16)) - 0.06;
    float d = min(min(body, bezel), min(needle, hub));
    for (int i = 0; i < 4; i++) {
        float a = 1.5707963 * float(i);
        d = min(d, length(p - float3(0.44 * sin(a), 0.44 * cos(a), 0.13)) - 0.035);
    }
    return d;
}

ORB_FORMA(bussola)
