#include "../OrbShading.h"

// Codice · build: an anvil with its horn to the left and a broad base; now and then a spark jumps off the face.
static float incudine(float3 p, float t) {
    float3 q = p - float3(0.15, 0.27, 0);
    float base = sdRoundBox(q - float3(0, -0.62, 0), float3(0.40, 0.10, 0.28), 0.04);
    float waist = sdRoundBox(q - float3(0, -0.35, 0), float3(0.22, 0.17, 0.20), 0.04);
    float face = sdRoundBox(q, float3(0.55, 0.17, 0.26), 0.06);
    float horn = sdRoundCone(q, float3(-0.45, 0, 0), float3(-0.95, 0.0, 0), 0.15, 0.04);
    float ph = fract(t / 3.0);
    float2 sp = float2(0.20 + 0.40 * ph, 0.22 + 2.0 * ph * (1.0 - ph));
    float spark = length(q - float3(sp, 0)) - 0.06 * (1.0 - smoothstep(0.3, 0.4, ph));
    return min(min(base, waist), min(min(face, horn), spark));
}

ORB_FORMA(incudine)
