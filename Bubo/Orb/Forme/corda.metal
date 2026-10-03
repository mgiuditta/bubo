#include "../OrbShading.h"

// Salute · movimento: a jump rope with two handles; the rope turns around the line between them.
static float corda(float3 p, float t) {
    float handles = min(sdCylinder(p - float3(-0.62, -0.4, 0), 0.08, 0.35), sdCylinder(p - float3(0.62, -0.4, 0), 0.08, 0.35));
    float c = cos(t * 2.0), s = sin(t * 2.0);
    float d = 9.0;
    float3 a = float3(-0.58, -0.05, 0);
    for (int i = 1; i <= 14; i++) {
        float x = -0.58 + 1.16 * float(i) / 14.0;
        float f = 0.85 * (1.0 - (x * x) / (0.58 * 0.58));
        float3 b = float3(x, -0.05 + f * c, f * s);
        d = min(d, sdSegment(p, a, b, 0.045));
        a = b;
    }
    return min(d, handles);
}

ORB_FORMA(corda)
