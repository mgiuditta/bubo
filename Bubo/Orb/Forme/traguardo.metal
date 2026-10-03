#include "../OrbShading.h"

// Agente · lavoro finito: a chequered flag on a pole; the whole flag swings around the pole as if in the wind.
static float traguardo(float3 p, float t) {
    const float poleX = -0.55;
    float a = 0.3 * sin(t * 2.2);
    float3 q = p;
    q.xz = (p.xz - float2(poleX, 0)) * rot(a) + float2(poleX, 0);
    float pole = sdSegment(q, float3(poleX, -0.92, 0), float3(poleX, 0.9, 0), 0.05);
    float ball = length(q - float3(poleX, 0.95, 0)) - 0.09;
    float cloth = extrude(sdRoundBox2(q.xy - float2(0.05, 0.575), float2(0.6, 0.4), 0.0), q.z, 0.035);
    float squares = 9.0;                               // the dark squares stand out of the cloth
    for (int j = 0; j < 4; j++) {
        for (int i = 0; i < 6; i++) {
            if ((i + j) % 2 == 0) {
                squares = min(squares, sdRoundBox2(q.xy - float2(-0.45 + 0.2 * float(i), 0.275 + 0.2 * float(j)), float2(0.095), 0.0));
            }
        }
    }
    float chequers = extrude(squares, q.z - 0.05, 0.05);
    return min(min(pole, ball), min(cloth, chequers));
}

ORB_FORMA(traguardo)
