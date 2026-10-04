#include "../OrbShading.h"

// Codice · scrittura: a matryoshka doll in profile, a small round head over a wide body, with a scarf and a flower on the belly.
static float matrioska(float3 p, float) {
    float body = sdRoundCone(p, float3(0, -0.4, 0), float3(0, 0, 0), 0.5, 0.4);
    float head = length(p - float3(0, 0.62, 0)) - 0.3;
    float scarf = length(float2(length(p.xz) - 0.26, p.y - 0.33)) - 0.05;
    float flower = min(sdTorusXY(p - float3(0, -0.3, 0.47), 0.14, 0.04), length(p - float3(0, -0.3, 0.5)) - 0.07);
    return min(min(body, head), min(scarf, flower));
}

ORB_FORMA(matrioska)
