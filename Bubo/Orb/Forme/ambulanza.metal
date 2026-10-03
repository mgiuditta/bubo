#include "../OrbShading.h"

// Salute · emergenze: an ambulance in profile with a red cross on its side; the roof light pulses and flashes.
static float ambulanza(float3 p, float t) {
    p.x -= 0.02;
    float2 q = p.xy;
    float van = sdRoundBox2(q - float2(-0.2, -0.05), float2(0.62, 0.4), 0.1);
    float cab = sdRoundBox2(q - float2(0.5, -0.2), float2(0.32, 0.25), 0.1);
    float shape = extrude(min(van, cab), p.z, 0.16) - 0.03;
    float3 m = float3(p.x, p.y, abs(p.z));
    float wheels = min(sdSegment(m, float3(-0.45, -0.55, 0.1), float3(-0.45, -0.55, 0.22), 0.18), sdSegment(m, float3(0.52, -0.55, 0.1), float3(0.52, -0.55, 0.22), 0.18));
    float cross = min(sdRoundBox(p - float3(-0.22, -0.02, 0.2), float3(0.22, 0.06, 0.03), 0.01), sdRoundBox(p - float3(-0.22, -0.02, 0.2), float3(0.06, 0.22, 0.03), 0.01));
    float beat = 0.5 + 0.5 * sin(t * 6.0);
    float3 c = p - float3(-0.1, 0.5, 0);
    float s = 1.0 + 0.4 * beat;
    float light = sdRoundBox(c / s, float3(0.12, 0.07, 0.1), 0.04) * s;
    float len = 0.03 + 0.17 * beat;
    float rays = min(sdSegment(float3(abs(c.x), c.y, c.z), float3(0.24, 0.04, 0), float3(0.24 + len, 0.04 + len, 0), 0.025), 9.0);
    return min(min(shape, wheels), min(cross, min(light, rays)));
}

ORB_FORMA(ambulanza)
