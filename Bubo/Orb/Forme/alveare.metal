#include "../OrbShading.h"

// The 2D regular hexagon of apothem r, flat sides up and down: exact inside and out.
static float alveareHexagon(float2 p, float r) {
    const float3 k = float3(-0.866025404, 0.5, 0.577350269);
    p = abs(p);
    p -= 2.0 * min(dot(k.xy, p), 0.0) * k.xy;
    p -= float2(clamp(p.x, -k.z * r, k.z * r), r);
    return length(p) * sign(p.y);
}

// Agente: a honeycomb of seven hexagonal cells, one in the middle and six around it, walls shared.
static float alveare(float3 p, float) {
    const float a = 0.27;                              // apothem of a cell
    float d = 9.0;
    for (int i = -1; i < 6; i++) {
        float2 c = float2(0);
        if (i >= 0) { float ang = 0.5235988 + 1.0471976 * float(i); c = 2.0 * a * float2(cos(ang), sin(ang)); }
        d = min(d, abs(alveareHexagon(p.xy - c, a - 0.03)) - 0.05); // a wall: exact outside both ways
    }
    return extrude(d, p.z, 0.05) - 0.02;
}

ORB_FORMA(alveare)
