#include "../OrbShading.h"

// Creativo: a light bulb with its screw cap; it switches on slowly, rays growing out of the glass.
static float lampadina(float3 p, float t) {
    p.y += 0.05;
    float bulb = length(p - float3(0, 0.2, 0)) - 0.45;
    float neck = sdCappedCone(p - float3(0, -0.14, 0), 0.14, 0.20, 0.32);
    float cap = min(sdCylinder(p - float3(0, -0.34, 0), 0.20, 0.045), sdCylinder(p - float3(0, -0.46, 0), 0.20, 0.045));
    float tip = length(p - float3(0, -0.56, 0)) - 0.09;
    float d = min(min(bulb, neck), min(cap, tip));
    float on = smoothstep(0.0, 1.0, 0.5 - 0.5 * cos(t * 1.1));  // t = 0 is off
    float3 q = float3(abs(p.x), p.y, p.z);
    for (int i = 0; i < 3; i++) {
        float ang = 0.9599 * float(i);                  // 0, 55 and 110 degrees from straight up
        float2 dir = float2(sin(ang), cos(ang));
        float2 a = float2(0, 0.2) + dir * 0.62;
        d = min(d, sdSegment(q, float3(a, 0), float3(a + dir * (0.02 + 0.22 * on), 0), 0.045));
    }
    return d;
}

ORB_FORMA(lampadina)
