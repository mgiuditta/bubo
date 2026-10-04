#include "../OrbShading.h"

// The tag's outline: a pentagon pointing up.
static float etichettaTag(float2 p) {
    const float2 v[5] = { float2(-0.40, -0.70), float2(0.40, -0.70), float2(0.40, 0.15), float2(0.0, 0.55), float2(-0.40, 0.15) };
    float d = dot2(p - v[0]), s = 1.0;
    for (int i = 0, j = 4; i < 5; j = i, i++) {
        float2 e = v[j] - v[i], w = p - v[i];
        d = min(d, dot2(w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0)));
        bool3 c = bool3(p.y >= v[i].y, p.y < v[j].y, e.x * w.y > e.y * w.x);
        if (all(c) || all(!c)) s = -s;
    }
    return s * sqrt(d);
}

// Codice: a tag with a hole and a loop of string, swinging from the top of the loop.
static float etichetta(float3 p, float t) {
    p.y -= 0.8;
    p.xy = p.xy * rot(0.25 * sin(t * 1.4));
    p.y += 0.9;
    float2 q = p.xy;
    float d = abs(etichettaTag(q)) - 0.03;
    d = min(d, abs(length(q - float2(0, 0.28)) - 0.10) - 0.03);
    d = min(d, abs(length(q - float2(0, 0.68)) - 0.22) - 0.025);
    return extrude(d, p.z, 0.03) - 0.03;
}

ORB_FORMA(etichetta)
