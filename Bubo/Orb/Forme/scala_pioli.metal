#include "../OrbShading.h"

// Agente · più sforzo: a straight ladder, two rails and five rungs.
static float scala_pioli(float3 p, float) {
    float d = sdSegment(float3(abs(p.x), p.y, p.z), float3(0.32, -0.92, 0), float3(0.32, 0.92, 0), 0.055);
    for (int i = 0; i < 5; i++) {
        float y = -0.6 + 0.3 * float(i);
        d = min(d, sdSegment(p, float3(-0.32, y, 0), float3(0.32, y, 0), 0.045));
    }
    return d;
}

ORB_FORMA(scala_pioli)
