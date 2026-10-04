#include "../OrbShading.h"

// Codice · rilascio: a cog with eight teeth and a hole in the middle, turning slowly.
static float ingranaggio(float3 p, float t) {
    float2 xy = p.xy * rot(-t * 0.5);
    float d = abs(length(xy) - 0.42) - 0.17;           // the rim, a shell: the hole stays open
    for (int i = 0; i < 8; i++) {
        float2 q = xy * rot(-0.7853982 * float(i));
        d = min(d, sdRoundBox2(q - float2(0, 0.66), float2(0.11, 0.14), 0.03));
    }
    return extrude(d, p.z, 0.07) - 0.03;
}

ORB_FORMA(ingranaggio)
