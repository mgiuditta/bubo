#include "../OrbShading.h"

// The ribbon bookmark: a strip with a V cut into its foot.
static float segnalibroRibbon(float2 p) {
    const float2 v[5] = { float2(-0.28, 0.80), float2(0.28, 0.80), float2(0.28, -0.80), float2(0.0, -0.45), float2(-0.28, -0.80) };
    float d = dot2(p - v[0]), s = 1.0;
    for (int i = 0, j = 4; i < 5; j = i, i++) {
        float2 e = v[j] - v[i], w = p - v[i];
        d = min(d, dot2(w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0)));
        bool3 c = bool3(p.y >= v[i].y, p.y < v[j].y, e.x * w.y > e.y * w.x);
        if (all(c) || all(!c)) s = -s;
    }
    return s * sqrt(d);
}

// Ricerca: a bookmark ribbon with a swallow-tail foot, leaning a little.
static float segnalibro(float3 p, float) {
    p.xy = p.xy * rot(0.25);
    return extrude(segnalibroRibbon(p.xy), p.z, 0.03) - 0.03;
}

ORB_FORMA(segnalibro)
