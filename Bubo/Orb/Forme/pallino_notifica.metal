#include "../OrbShading.h"

// Mail · avvisi: a notification badge, a round disc with a raised "1" on it, pulsing like a new alert.
static float pallino_notifica(float3 p, float t) {
    float s = 1.0 + 0.10 * pulse(fract(t / 1.6), 0.25, 0.20);
    p /= s;
    float d = extrude(length(p.xy) - 0.62, p.z, 0.05) - 0.05;
    d = min(d, sdSegment(p, float3(0.02, 0.36, 0.12), float3(0.02, -0.34, 0.12), 0.065));
    d = min(d, sdSegment(p, float3(0.02, 0.36, 0.12), float3(-0.17, 0.22, 0.12), 0.06));
    return d * s;
}

ORB_FORMA(pallino_notifica)
