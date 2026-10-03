#include "../OrbShading.h"

// Codice: an asterisk with six rounded arms; every few seconds it turns a sixth of a turn, which looks the same.
static float asterisco(float3 p, float t) {
    float a = (M_PI_F / 3.0) * smoothstep(0.7, 1.0, fract(t / 3.0));
    float2 q = p.xy * rot(a);
    float d = 1e3;
    for (int i = 0; i < 3; i++) {
        float angle = M_PI_F * 0.5 + float(i) * (M_PI_F / 3.0);
        float2 dir = float2(cos(angle), sin(angle)) * 0.78;
        d = min(d, udSegment2(q, -dir, dir));
    }
    return extrude(d - 0.04, p.z, 0.03) - 0.04;
}

ORB_FORMA(asterisco)
