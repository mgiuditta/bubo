#include "../OrbShading.h"

// Musica: a trumpet in profile, bell to the right: mouthpiece, lead pipe, loop, three valves.
static float tromba(float3 p, float) {
    p.x += 0.03;
    float mouth = sdRoundCone(p, float3(-0.92, 0.05, 0), float3(-0.74, 0.05, 0), 0.065, 0.03);
    float pipe = sdSegment(p, float3(-0.74, 0.05, 0), float3(0.30, 0.05, 0), 0.04);
    float bell = sdCappedCone(float3(p.y - 0.05, p.x - 0.575, p.z), 0.275, 0.05, 0.30);
    float loop = extrude(abs(sdRoundBox2(p.xy - float2(-0.05, -0.12), float2(0.50, 0.18), 0.18)) - 0.015, p.z, 0.01) - 0.03;
    float d = min(min(mouth, pipe), min(bell, loop));
    for (int i = 0; i < 3; i++) {
        float x = -0.25 + 0.20 * float(i);
        d = min(d, sdSegment(p, float3(x, 0.04, 0), float3(x, 0.30, 0), 0.045));
        d = min(d, length(p - float3(x, 0.33, 0)) - 0.07);
    }
    return d;
}

ORB_FORMA(tromba)
