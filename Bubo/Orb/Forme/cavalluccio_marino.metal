#include "../OrbShading.h"

// Chat · natura: a seahorse in profile, curled tail, snout and crown; it sways like in a current.
static float cavalluccio_marino(float3 p, float t) {
    p.xy = p.xy * rot(0.1 * sin(t * 1.2));
    float head = length(p - float3(0.0, 0.55, 0)) - 0.16;
    float snout = sdSegment(p, float3(0.1, 0.55, 0), float3(0.4, 0.5, 0), 0.05);
    float crown = length(p - float3(-0.04, 0.74, 0)) - 0.05;
    float belly = sdRoundCone(p, float3(-0.03, 0.38, 0), float3(0, -0.1, 0), 0.18, 0.22);
    float fin = length(p - float3(-0.22, 0.12, 0)) - 0.07;
    float tail = min(min(sdRoundCone(p, float3(0, -0.1, 0), float3(-0.05, -0.45, 0), 0.2, 0.1),
                         sdRoundCone(p, float3(-0.05, -0.45, 0), float3(-0.22, -0.66, 0), 0.1, 0.08)),
                     min(sdRoundCone(p, float3(-0.22, -0.66, 0), float3(-0.42, -0.58, 0), 0.08, 0.06),
                         sdRoundCone(p, float3(-0.42, -0.58, 0), float3(-0.36, -0.4, 0), 0.06, 0.04)));
    return min(min(min(head, snout), min(crown, belly)), min(fin, tail));
}

ORB_FORMA(cavalluccio_marino)
