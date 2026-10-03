#include "../OrbShading.h"

// Chat · conversazione: a ballot box whose lid is split by a slot, a ballot sinking into it again and again.
static float urna_elettorale(float3 p, float t) {
    float body = sdRoundBox(p - float3(0, -0.3, 0), float3(0.6, 0.45, 0.35), 0.08);
    float3 q = float3(abs(p.x), p.y, p.z);
    float lid = sdRoundBox(q - float3(0.38, 0.2, 0), float3(0.28, 0.05, 0.4), 0.05);
    float drop = 0.35 * fract(t / 3.0);
    float ballot = sdRoundBox(p - float3(0, 0.45 - drop, 0), float3(0.03, 0.25, 0.15), 0.02);
    return min(min(body, lid), ballot);
}

ORB_FORMA(urna_elettorale)
