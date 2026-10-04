#include "../OrbShading.h"

// Codice · rilascio: a square terminal window with the prompt >_ raised on its front; the cursor blinks.
static float terminale(float3 p, float t) {
    float window = sdRoundBox(p, float3(0.84, 0.66, 0.08), 0.08);
    float d = window;
    for (int i = 0; i < 3; i++) {                      // the title bar's three buttons
        d = min(d, length(p - float3(-0.64 + 0.15 * float(i), 0.48, 0.09)) - 0.045);
    }
    float chevron = min(sdSegment(p, float3(-0.50, 0.22, 0.10), float3(-0.22, 0.0, 0.10), 0.065),
                        sdSegment(p, float3(-0.22, 0.0, 0.10), float3(-0.50, -0.22, 0.10), 0.065));
    float off = smoothstep(0.45, 0.55, fract(t / 1.1)); // 1 while the cursor is hidden
    float z = 0.10 - 0.14 * off;                       // it sinks into the window
    float cursor = sdSegment(p, float3(-0.06, -0.24, z), float3(0.30, -0.24, z), 0.065);
    return min(min(d, chevron), cursor);
}

ORB_FORMA(terminale)
