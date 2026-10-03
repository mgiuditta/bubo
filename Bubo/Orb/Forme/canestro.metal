#include "../OrbShading.h"

// Salute · movimento: a basketball hoop, a backboard on a pole with a tilted rim and a net of eight strands that sways.
static float canestro(float3 p, float t) {
    const float3 centre = float3(0, -0.05, 0.38);
    const float R = 0.25, tilt = 0.55;
    float board = sdRoundBox(p - float3(0, 0.4, -0.2), float3(0.55, 0.38, 0.05), 0.04);
    float target = sdRoundBox(p - float3(0, 0.1, -0.14), float3(0.18, 0.14, 0.02), 0.015);
    float pole = sdSegment(p, float3(0, 0.0, -0.25), float3(0, -0.9, -0.3), 0.06);
    float arm = sdSegment(p, float3(0, 0.08, 0.17), float3(0, 0.08, -0.15), 0.03);
    float3 q = p - centre;
    q.yz = q.yz * rot(-tilt);
    float d = min(min(board, target), min(pole, arm));
    d = min(d, length(float2(length(q.xz) - R, q.y)) - 0.035);
    float sway = 0.05 * sin(t * 3.0);
    for (int i = 0; i < 8; i++) {
        float a = float(i) * 0.7854;
        float2 ring = float2(cos(a), sin(a));
        float3 top = centre + float3(R * ring.x, -R * ring.y * sin(tilt), R * ring.y * cos(tilt));
        float3 bottom = centre + float3(0.55 * R * ring.x + sway, -0.5 - 0.55 * R * ring.y * sin(tilt), 0.55 * R * ring.y * cos(tilt));
        d = min(d, sdSegment(p, top, bottom, 0.015));
    }
    return d;
}

ORB_FORMA(canestro)
