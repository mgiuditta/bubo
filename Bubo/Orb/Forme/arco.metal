#include "../OrbShading.h"

// Salute · tiro con l'arco: a bow drawn back, the string pulled to the nock of an arrow that points past the grip.
static float arco(float3 p, float) {
    p.x -= 0.275;
    float d = 9.0;
    float2 a = float2(0, 0.88);
    for (int i = 1; i <= 8; i++) {
        float y = 0.88 - 1.76 * float(i) / 8.0;
        float2 b = float2(-0.5 * (1.0 - (y / 0.88) * (y / 0.88)), y);
        d = min(d, sdSegment(p, float3(a, 0), float3(b, 0), 0.05));
        a = b;
    }
    float grip = sdSegment(p, float3(-0.5, -0.17, 0), float3(-0.5, 0.17, 0), 0.075);
    float string = min(sdSegment(p, float3(0, 0.88, 0), float3(0.38, 0, 0), 0.02), sdSegment(p, float3(0, -0.88, 0), float3(0.38, 0, 0), 0.02));
    float shaft = sdSegment(p, float3(0.38, 0, 0), float3(-0.78, 0, 0), 0.03);
    float head = sdRoundCone(p, float3(-0.7, 0, 0), float3(-0.97, 0, 0), 0.08, 0.012);
    float fletch = min(sdSegment(p, float3(0.3, 0, 0), float3(0.42, 0.13, 0), 0.025), sdSegment(p, float3(0.3, 0, 0), float3(0.42, -0.13, 0), 0.025));
    return min(min(min(d, grip), min(string, shaft)), min(head, fletch));
}

ORB_FORMA(arco)
