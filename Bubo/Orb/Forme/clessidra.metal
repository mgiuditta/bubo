#include "../OrbShading.h"

// Tempo: an hourglass frame with its sand. The sand runs from the top cone into a growing pile,
// then the frame turns over and starts again.
static float clessidra(float3 p, float t) {
    const float period = 8.0, flow = 0.85;             // fraction of the period spent flowing
    float phase = fract(t / period + 0.42);            // t = 0 is halfway through
    float f = min(phase / flow, 1.0);                  // how much sand has fallen
    p.xy = p.xy * rot(M_PI_F * smoothstep(flow, 1.0, phase));
    float3 q = float3(abs(p.x), abs(p.y), p.z);
    float plate = sdCylinder(q - float3(0, 0.80, 0), 0.50, 0.035) - 0.025;
    float post = sdSegment(q, float3(0.44, 0, 0), float3(0.44, 0.78, 0), 0.04);
    const float neck = 0.05, rim = 0.66, wide = 0.40, narrow = 0.03;
    float level = neck + (rim - neck) * (1.0 - f);     // top of the sand above the neck
    float topH = max((level - neck) * 0.5, 0.004);
    float upper = sdCappedCone(p - float3(0, neck + topH, 0), topH,
                               narrow, narrow + (wide - narrow) * (1.0 - f));
    float pileH = max((rim - neck) * f * 0.5, 0.004);
    float lower = sdCappedCone(p - float3(0, -rim + pileH, 0), pileH, narrow + (wide - narrow) * f, narrow);
    float d = min(min(plate, post), min(upper, lower));
    if (f < 0.98) d = min(d, sdSegment(p, float3(0, neck, 0), float3(0, -rim + 2.0 * pileH, 0), 0.016));
    return d;
}

ORB_FORMA(clessidra)
