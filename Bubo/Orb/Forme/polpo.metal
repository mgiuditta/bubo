#include "../OrbShading.h"

// Chat · creature marine e fondali: an octopus, a round head with two eyes and eight tentacles that wave.
static float polpo(float3 p, float t) {
    p.y -= 0.1;
    float head = length(p - float3(0, 0.3, 0)) - 0.45;
    float eyes = length(float3(abs(p.x), p.y, p.z) - float3(0.17, 0.3, 0.4)) - 0.07;
    float d = min(head, eyes);
    for (int i = 0; i < 8; i++) {
        float x0 = -0.36 + 0.103 * float(i);
        float2 a = float2(x0, -0.05);
        for (int j = 0; j < 4; j++) {
            float f = float(j + 1);
            float2 b = float2(x0 * (1.0 + 0.22 * f) + 0.07 * f * sin(t * 2.0 + f * 1.1 + float(i)), -0.05 - 0.23 * f);
            d = min(d, sdSegment(p, float3(a, 0), float3(b, 0), 0.075 - 0.011 * f));
            a = b;
        }
    }
    return d;
}

ORB_FORMA(polpo)
