// The Orb's shader with one more kernel, built into the test bundle only: FormaTests reads each
// Forma's distance at chosen points through it. The FORMA function constant picks the Forma.
#include "../Bubo/Orb/Orb.metal"

// The distance of the pipeline's Forma at each point's xyz, at shader time w.
kernel void formaProbe(device const float4 *points [[buffer(0)]], device float *distances [[buffer(1)]],
                       uint i [[thread_position_in_grid]]) {
    distances[i] = forma(points[i].xyz, points[i].w);
}
