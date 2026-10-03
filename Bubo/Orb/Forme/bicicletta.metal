#include "../OrbShading.h"

// Salute · movimento: a bicycle in profile; the wheels turn on their spokes.
static float bicicletta(float3 p, float t) {
    const float3 rear = float3(-0.52, -0.25, 0), front = float3(0.52, -0.25, 0);
    const float3 bb = float3(-0.06, -0.25, 0), seat = float3(-0.24, 0.28, 0), head = float3(0.36, 0.28, 0);
    float d = min(sdTorusXY(p - rear, 0.36, 0.04), sdTorusXY(p - front, 0.36, 0.04));
    for (int i = 0; i < 2; i++) {
        float a = t * 2.5 + 1.5707963 * float(i);
        float3 s = 0.34 * float3(cos(a), sin(a), 0);
        d = min(d, min(sdSegment(p, rear - s, rear + s, 0.025), sdSegment(p, front - s, front + s, 0.025)));
    }
    float frame = min(min(sdSegment(p, rear, bb, 0.04), sdSegment(p, rear, seat, 0.04)),
                      min(sdSegment(p, bb, seat, 0.04), sdSegment(p, bb, head, 0.04)));
    frame = min(frame, min(sdSegment(p, seat, head, 0.04), sdSegment(p, head, front, 0.04)));
    float3 grip = head + float3(-0.08, 0.24, 0);
    float bars = min(sdSegment(p, head, grip, 0.04), sdSegment(p, grip, grip + float3(0.16, 0.04, 0), 0.04));
    float saddle = sdSegment(p, seat + float3(-0.08, 0.08, 0), seat + float3(0.10, 0.08, 0), 0.05);
    return min(min(d, frame), min(bars, saddle));
}

ORB_FORMA(bicicletta)
