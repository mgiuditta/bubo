#include "../OrbShading.h"

// Musica · jazz: a saxophone, a J with the bell turned up and the mouthpiece on a bent neck.
static float sassofono(float3 p, float) {
    float d = sdRoundCone(p, float3(-0.30, 0.55, 0), float3(-0.25, -0.45, 0), 0.07, 0.12);
    float bend = min(udQuarterArc(p.xy, float2(0.05, -0.45), 0.30, float2(1, -1)),
                     udQuarterArc(p.xy, float2(0.05, -0.45), 0.30, float2(-1, -1)));
    d = min(d, length(float2(bend, p.z)) - 0.12);
    d = min(d, sdRoundCone(p, float3(0.35, -0.45, 0), float3(0.40, 0.25, 0), 0.12, 0.27));
    d = min(d, sdSegment(p, float3(-0.55, 0.82, 0), float3(-0.30, 0.55, 0), 0.05));
    for (int i = 0; i < 3; i++) d = min(d, length(p - float3(-0.27, 0.25 - 0.20 * float(i), 0.13)) - 0.05);
    return d;
}

ORB_FORMA(sassofono)
