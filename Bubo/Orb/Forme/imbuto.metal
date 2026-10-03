#include "../OrbShading.h"

// Chat · conversazione: a funnel with a short spout; a drop swells at the tip and falls.
static float imbuto(float3 p, float t) {
    p.y -= 0.10;
    float cone = sdCappedCone(p - float3(0, 0.22, 0), 0.30, 0.09, 0.62);
    float rim = length(float2(length(p.xz) - 0.62, p.y - 0.52)) - 0.05;
    float spout = sdCylinder(p - float3(0, -0.22, 0), 0.09, 0.16);
    float phase = fract(t / 1.8);
    float s = mix(0.15, 1.0, smoothstep(0.0, 0.45, phase));        // it swells,
    float y = -0.46 - 0.42 * smoothstep(0.55, 1.0, phase) * s;     // then falls
    float drop = sdRoundCone(p, float3(0, y, 0), float3(0, y + 0.09 * s, 0), 0.07 * s, 0.02 * s);
    return min(min(cone, rim), min(spout, drop));
}

ORB_FORMA(imbuto)
