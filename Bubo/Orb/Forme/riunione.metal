#include "../OrbShading.h"

// Tempo: a round table seen from above with four chairs, each a rounded seat.
static float riunione(float3 p, float) {
    float2 q = p.xy * rot(0.3);                        // off the grid's diagonals, which are creases of a four-fold shape
    float d = length(q) - 0.36;
    for (int k = 0; k < 4; k++) {
        float2 c = q * rot(float(k) * M_PI_F * 0.5);
        d = min(d, sdRoundBox2(c - float2(0.66, 0), float2(0.17), 0.06));
    }
    return extrude(d, p.z, 0.04) - 0.02;
}

ORB_FORMA(riunione)
