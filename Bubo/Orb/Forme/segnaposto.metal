#include "../OrbShading.h"

// Ricerca: a map pin, a teardrop with a ring in its head, hopping on the spot.
static float segnaposto(float3 p, float t) {
    p.y -= 0.08 * abs(sin(t * 3.0));
    float pin = sdRoundCone(p, float3(0, 0.20, 0), float3(0, -0.80, 0), 0.38, 0.02);
    float ring = sdTorusXY(p - float3(0, 0.20, 0.35), 0.15, 0.05);
    return min(pin, ring);
}

ORB_FORMA(segnaposto)
