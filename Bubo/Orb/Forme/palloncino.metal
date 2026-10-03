#include "../OrbShading.h"

// Codice: a round balloon with its knot and a wavy string; it swells and shrinks slowly.
static float palloncino(float3 p, float t) {
    float s = 1.0 + 0.07 * sin(t * 1.1);
    p /= s;
    p.y -= 0.12;
    float balloon = length(p - float3(0, 0.2, 0)) - 0.52;
    float knot = sdCappedCone(p - float3(0, -0.34, 0), 0.07, 0.11, 0.04);
    float string = sdSegment(p, float3(0, -0.40, 0), float3(0.09, -0.60, 0), 0.025);
    string = min(string, sdSegment(p, float3(0.09, -0.60, 0), float3(-0.07, -0.78, 0), 0.025));
    string = min(string, sdSegment(p, float3(-0.07, -0.78, 0), float3(0.05, -0.95, 0), 0.025));
    return min(balloon, min(knot, string)) * s;
}

ORB_FORMA(palloncino)
