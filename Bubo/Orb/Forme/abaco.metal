#include "../OrbShading.h"

// Ricerca: an abacus, a frame with four rows of beads; one bead slides along its rod.
static float abaco(float3 p, float t) {
    const float r = 0.055;
    float d = sdSegment(p, float3(-0.85, 0.65, 0), float3(0.85, 0.65, 0), r);
    d = min(d, sdSegment(p, float3(-0.85, -0.65, 0), float3(0.85, -0.65, 0), r));
    d = min(d, sdSegment(p, float3(-0.85, 0.65, 0), float3(-0.85, -0.65, 0), r));
    d = min(d, sdSegment(p, float3(0.85, 0.65, 0), float3(0.85, -0.65, 0), r));
    const int left[4] = { 4, 2, 3, 1 };
    float slide = 0.5 - 0.5 * cos(t);
    for (int row = 0; row < 4; row++) {
        float y = 0.39 - 0.26 * float(row);
        d = min(d, sdSegment(p, float3(-0.8, y, 0), float3(0.8, y, 0), 0.03));
        for (int i = 0; i < 6; i++) {
            float x = i < left[row] ? -0.65 + 0.2 * float(i) : 0.65 - 0.2 * float(5 - i);
            if (row == 2 && i == 2) x += 0.3 * slide;
            d = min(d, length(p - float3(x, y, 0)) - 0.11);
        }
    }
    return d;
}

ORB_FORMA(abaco)
