#include "../OrbShading.h"

// Salute · mobilità ridotta: a wheelchair in profile, a big spoked wheel that turns, a caster, a seat, back and footrest.
static float sedia_a_rotelle(float3 p, float t) {
    p.y -= 0.05;
    float3 w = p - float3(-0.1, -0.4, 0.14);
    float d = sdTorusXY(w, 0.45, 0.055);
    d = min(d, sdSegment(w, float3(0, 0, -0.04), float3(0, 0, 0.04), 0.06));
    for (int i = 0; i < 6; i++) {
        float a = float(i) * M_PI_F / 3.0 + t * 1.2;
        d = min(d, sdSegment(w, float3(0, 0, 0), float3(0.45 * cos(a), 0.45 * sin(a), 0), 0.03));
    }
    float caster = sdTorusXY(p - float3(0.62, -0.72, 0.14), 0.13, 0.05);
    float seat = sdSegment(p, float3(-0.4, 0.02, 0), float3(0.42, 0.02, 0), 0.07);
    float back = sdSegment(p, float3(-0.4, 0.02, 0), float3(-0.55, 0.72, 0), 0.05);
    float handle = sdSegment(p, float3(-0.55, 0.72, 0), float3(-0.82, 0.72, 0), 0.05);
    float arm = min(sdSegment(p, float3(-0.45, 0.32, 0), float3(0.15, 0.32, 0), 0.04), sdSegment(p, float3(0.15, 0.32, 0), float3(0.15, 0.02, 0), 0.04));
    float legs = min(sdSegment(p, float3(0.42, 0.02, 0), float3(0.62, -0.5, 0), 0.05), sdSegment(p, float3(0.62, -0.5, 0), float3(0.82, -0.52, 0), 0.05));
    float fork = sdSegment(p, float3(0.55, -0.6, 0.0), float3(0.62, -0.72, 0.14), 0.035);
    float frame = sdSegment(p, float3(-0.1, -0.4, 0), float3(0.3, 0.02, 0), 0.04);
    return min(min(min(d, caster), min(seat, back)), min(min(handle, arm), min(legs, min(fork, frame))));
}

ORB_FORMA(sedia_a_rotelle)
