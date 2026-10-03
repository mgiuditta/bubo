#include "../OrbShading.h"

// Musica: a hunting horn, two coils of tube, a small mouthpiece and the wide bell flaring to the right.
static float corno(float3 p, float) {
    float3 c = p - float3(-0.25, 0, 0);
    float d = min(sdTorusXY(c, 0.5, 0.07), sdTorusXY(c, 0.32, 0.07));
    float3 b = p - float3(0.6, 0, 0);
    float bell = sdCappedCone(float3(b.y, b.x, b.z), 0.3, 0.06, 0.4);
    float mouth = min(sdSegment(p, float3(-0.6, 0.35, 0), float3(-0.8, 0.62, 0), 0.05), length(p - float3(-0.82, 0.65, 0)) - 0.09);
    return min(min(d, bell), mouth);
}

ORB_FORMA(corno)
