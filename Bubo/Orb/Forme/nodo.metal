#include "../OrbShading.h"

// A point of the trefoil curve, centred and scaled to fit the Orb.
static float3 nodoPoint(float a) {
    const float s = 0.26;
    return float3(sin(a) + 2.0 * sin(2.0 * a), cos(a) - 2.0 * cos(2.0 * a) + 0.47, -sin(3.0 * a)) * s;
}

// Chat · conversazione: a trefoil knot of rope, tightened.
static float nodo(float3 p, float) {
    float d = 9.0;
    float3 a = nodoPoint(0.0);
    for (int i = 1; i <= 18; i++) {
        float3 b = nodoPoint(float(i) * (2.0 * M_PI_F / 18.0));
        d = min(d, sdSegment(p, a, b, 0.11));
        a = b;
    }
    return d;
}

ORB_FORMA(nodo)
