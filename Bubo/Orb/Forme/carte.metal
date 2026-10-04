#include "../OrbShading.h"

// One card of the fan, turned by `angle` around the pivot at the fan's foot and pushed back by `z`.
static float carteCard(float3 p, float angle, float z) {
    float3 q = p - float3(0, -0.62, 0);
    q.xy = q.xy * rot(angle);
    q.z -= z;
    return extrude(sdRoundBox2(q.xy - float2(0, 0.38), float2(0.25, 0.38), 0.05), q.z, 0.02) - 0.01;
}

// Chat · conversazione: a fan of three playing cards, opening and closing a little.
static float carte(float3 p, float t) {
    float spread = 0.5 * (0.8 + 0.2 * sin(t * 0.9));
    float d = min(carteCard(p, -spread, -0.065), carteCard(p, 0.0, 0.0));
    return min(d, carteCard(p, spread, 0.065));
}

ORB_FORMA(carte)
