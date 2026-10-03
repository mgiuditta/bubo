#include "../OrbShading.h"

// Ricerca · novità: a lattice radio mast with waves spreading from its tip on both sides.
static float antennaHalfWidth(float y) { return 0.4 * (0.5 - y) / 1.38; }

static float antenna(float3 p, float t) {
    const float3 tip = float3(0, 0.5, 0);
    float3 q = float3(abs(p.x), p.y, p.z);
    float d = sdSegment(q, float3(0.4, -0.88, 0), tip, 0.04);
    d = min(d, length(p - tip) - 0.07);
    const float levels[5] = { -0.88, -0.55, -0.22, 0.11, 0.44 };
    for (int i = 0; i < 4; i++) {
        float y0 = levels[i], y1 = levels[i + 1];
        float s = i % 2 == 0 ? 1.0 : -1.0;
        d = min(d, sdSegment(p, float3(-s * antennaHalfWidth(y0), y0, 0), float3(s * antennaHalfWidth(y1), y1, 0), 0.03));
        if (i > 0) d = min(d, sdSegment(p, float3(-antennaHalfWidth(y0), y0, 0), float3(antennaHalfWidth(y0), y0, 0), 0.03));
    }
    d = min(d, sdSegment(p, float3(-0.4, -0.88, 0), float3(0.4, -0.88, 0), 0.03));
    for (int i = 0; i < 2; i++) {
        float ph = fract(t * 0.4 + 0.5 * float(i));
        float R = 0.18 + 0.45 * ph;
        float2 c = q.xy - tip.xy;
        float arc = min(udQuarterArc(c, float2(0), R, float2(1, 1)), udQuarterArc(c, float2(0), R, float2(1, -1)));
        d = min(d, length(float2(arc, p.z)) - 0.045 * sin(3.1416 * ph));
    }
    return d;
}

ORB_FORMA(antenna)
