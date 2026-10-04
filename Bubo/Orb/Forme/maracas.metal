#include "../OrbShading.h"

// Un maraca dritto: a ball on a handle with a knob, pointing up from the origin.
static float maracasOne(float3 p) {
    return min(min(length(p - float3(0, 0.5, 0)) - 0.24, sdSegment(p, float3(0, 0.3, 0), float3(0, -0.5, 0), 0.055)),
               length(p - float3(0, -0.55, 0)) - 0.09);
}

// Musica: two maracas crossed in an X, shaken in turn.
static float maracas(float3 p, float t) {
    float shake = 0.12 * sin(t * 10.0);
    float3 a = p, b = p;
    a.xy = a.xy * rot(0.6 + shake);
    b.xy = b.xy * rot(-0.6 - shake);
    return min(maracasOne(a), maracasOne(b));
}

ORB_FORMA(maracas)
