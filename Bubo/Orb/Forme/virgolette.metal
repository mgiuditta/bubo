#include "../OrbShading.h"

// Ricerca · citazioni: two tall quotation marks, each a round head with a tail curling down.
static float virgolette(float3 p, float) {
    float d = 1e3;
    for (int i = 0; i < 2; i++) {
        float cx = i == 0 ? -0.42 : 0.42;
        d = min(d, sdRoundCone(p, float3(cx - 0.24, -0.55, 0), float3(cx, 0.35, 0), 0.09, 0.30));
    }
    return d;
}

ORB_FORMA(virgolette)
