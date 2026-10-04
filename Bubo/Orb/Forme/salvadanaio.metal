#include "../OrbShading.h"

// Finanza: a piggy bank in profile, snout to the right, with the coin slot on its back.
static float salvadanaio(float3 p, float) {
    float body = length(p - float3(-0.05, -0.05, 0)) - 0.55;
    float snout = sdSegment(p, float3(0.50, -0.03, 0), float3(0.64, -0.03, 0), 0.17);
    float ear = sdRoundCone(p, float3(0.12, 0.46, 0.12), float3(0.26, 0.70, 0.12), 0.10, 0.04);
    float d = min(min(body, snout), ear);
    for (int i = 0; i < 4; i++) {                      // legs
        float x = i < 2 ? -0.36 : 0.22;
        float z = (i % 2 == 0) ? -0.2 : 0.2;
        d = min(d, sdSegment(p, float3(x, -0.40, z), float3(x, -0.72, z), 0.10));
    }
    d = min(d, sdSegment(p, float3(-0.28, 0.55, 0), float3(0.06, 0.55, 0), 0.04));    // the slot
    d = min(d, sdSegment(p, float3(-0.58, 0.05, 0), float3(-0.72, 0.22, 0), 0.04));   // the tail
    d = min(d, sdSegment(p, float3(-0.72, 0.22, 0), float3(-0.64, 0.34, 0), 0.04));
    d = min(d, length(p - float3(0.36, 0.20, 0.30)) - 0.055);                          // the eye
    return d;
}

ORB_FORMA(salvadanaio)
