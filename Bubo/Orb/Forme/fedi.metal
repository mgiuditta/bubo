#include "../OrbShading.h"

// Chat: two wedding rings side by side, each turned a little, overlapping.
static float fedi(float3 p, float) {
    float3 a = p - float3(-0.27, 0, 0);
    a.xz = a.xz * rot(0.5);
    float3 b = p - float3(0.27, 0, 0);
    b.xz = b.xz * rot(-0.5);
    return min(sdTorusXY(a, 0.46, 0.08), sdTorusXY(b, 0.46, 0.08));
}

ORB_FORMA(fedi)
