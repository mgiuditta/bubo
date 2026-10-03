#include "../OrbShading.h"

// Musica: a loudspeaker cabinet turned a little, with a big woofer cone and a small tweeter cone that stand out and pulse to the beat.
static float altoparlante(float3 p, float t) {
    p.xz = p.xz * rot(0.6);
    float s = 1.0 + 0.12 * sin(t * 8.0);
    float d = sdRoundBox(p, float3(0.48, 0.85, 0.16), 0.06);
    // The cones' axes are z; swapping y and z gives them the y axis the primitive wants.
    d = min(d, sdCappedCone(float3(p.x, p.z - 0.20, p.y + 0.25), 0.10, 0.12, 0.30 * s));
    d = min(d, sdCappedCone(float3(p.x, p.z - 0.20, p.y - 0.45), 0.08, 0.06, 0.15 * s));
    return d;
}

ORB_FORMA(altoparlante)
