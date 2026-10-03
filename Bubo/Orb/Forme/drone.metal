#include "../OrbShading.h"

// Agente: a quadcopter seen from above, a rotor at the end of each arm, the blades turning.
static float drone(float3 p, float t) {
    float d = extrude(sdRoundBox2(p.xy, float2(0.25, 0.20), 0.10), p.z, 0.07) - 0.03;
    for (int i = 0; i < 4; i++) {
        float2 s = float2(i % 2 == 0 ? 1.0 : -1.0, i < 2 ? 1.0 : -1.0);
        float3 hub = float3(0.45 * s.x, 0.42 * s.y, 0);
        float a = t * 14.0 * s.x * s.y;
        float3 b1 = 0.24 * float3(cos(a), sin(a), 0), b2 = 0.24 * float3(-sin(a), cos(a), 0);
        d = min(d, sdSegment(p, float3(0), hub, 0.05));
        d = min(d, length(p - hub) - 0.09);
        d = min(d, min(sdSegment(p, hub - b1, hub + b1, 0.03), sdSegment(p, hub - b2, hub + b2, 0.03)));
    }
    return d;
}

ORB_FORMA(drone)
