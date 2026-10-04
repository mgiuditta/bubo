#include "../OrbShading.h"

// Meteo: a zig-zag lightning bolt that flashes now and then, swelling twice like a strike.
static float fulmine(float3 p, float t) {
    float phase = fract(t / 3.5 + 0.5);                // t = 0 is between flashes
    float s = 1.0 + 0.08 * pulse(phase, 0.10, 0.05) + 0.05 * pulse(phase, 0.22, 0.05);
    p /= s;
    const float2 a = float2(0.12, 0.92), b = float2(-0.44, -0.06), c = float2(-0.02, -0.06),
                 d = float2(-0.20, -0.92), e = float2(0.46, 0.16), f = float2(0.06, 0.16);
    float bolt = min(sdQuad2(p.xy, a, b, c, f), sdQuad2(p.xy, c, d, e, f));
    return (extrude(bolt, p.z, 0.07) - 0.04) * s;
}

ORB_FORMA(fulmine)
