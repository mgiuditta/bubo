#include "../OrbShading.h"

// Tempo: a sundial: a round plate with hour marks and a triangular gnomon, tipped toward the camera.
static float meridiana(float3 p, float) {
    float3 q = p;
    q.yz = p.yz * rot(-0.8);
    float plate = sdCylinder(q, 0.80, 0.05);
    float gnomon = extrude(sdQuad2(q.zy, float2(-0.42, 0.05), float2(0.42, 0.05), float2(0.42, 0.13), float2(-0.42, 0.56)), q.x, 0.035) - 0.01;
    float marks = 9.0;
    for (int i = 0; i < 8; i++) {                      // eight hour marks around the rim
        float a = 0.7853982 * float(i);
        marks = min(marks, length(q - float3(0.68 * cos(a), 0.06, 0.68 * sin(a))) - 0.06);
    }
    return min(min(plate, gnomon), marks);
}

ORB_FORMA(meridiana)
