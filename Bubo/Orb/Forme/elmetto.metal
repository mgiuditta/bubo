#include "../OrbShading.h"

// Codice · modifiche ampie: a hard hat, a dome with a wide brim and a ridge along the top.
static float elmettoDome(float2 p, float r) {
    if (p.y >= 0.0) return max(length(p) - r, -p.y);
    return length(float2(p.x - clamp(p.x, -r, r), p.y));
}

static float elmetto(float3 p, float) {
    float d = elmettoDome(p.xy - float2(0, -0.15), 0.62);
    d = min(d, sdRoundBox2(p.xy - float2(0, -0.15), float2(0.85, 0.06), 0.05));
    d = min(d, sdRoundBox2(p.xy - float2(0, 0.50), float2(0.10, 0.12), 0.02));
    return extrude(d, p.z, 0.10) - 0.04;
}

ORB_FORMA(elmetto)
