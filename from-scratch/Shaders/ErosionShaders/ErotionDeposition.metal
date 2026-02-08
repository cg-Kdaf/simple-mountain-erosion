//
//  ErotionDeposition.metal
//  from-scratch
//
//  Created by Colin Marmond on 08/02/2026.
//

#include <metal_stdlib>
#include "../CommonShaders.h"
using namespace metal;

kernel void erosion_deposition(
    texture2d<float, access::read> terrainRead [[texture(0)]],
    texture2d<float, access::write> terrainWrite [[texture(1)]],
    texture2d<float, access::read> velocity [[texture(2)]],
    constant HeightMapUniforms& hmU [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= terrainRead.get_width() || gid.y >= terrainRead.get_height()) return;
    
    int2 pos = int2(gid);
    float4 state = terrainRead.read(gid); // b, r, d, s
    float b = state.r; // Bedrock
    float r = state.g; // Regolith
    float d = state.b; // Water
    float s = state.a; // Sediment

    float2 vel = velocity.read(gid).xy;
    float speed = length(vel);

    // Calculate Slope (Local Tilt)
    // Simple gradient approximation
    float h = b + r;
    float hR = read_tex(terrainRead, pos + int2(1,0)).r + read_tex(terrainRead, pos + int2(1,0)).g;
    float hT = read_tex(terrainRead, pos + int2(0,1)).r + read_tex(terrainRead, pos + int2(0,1)).g;
    float2 grad = float2(hR - h, hT - h);
    float tilt = length(grad);

    // 1. Capacity (C)
    float C = hmU.Kc * tilt * speed;
    // Usually clamped to avoid infinite erosion on cliffs or zero on flat
    C = max(0.001, C);

    if (s > C) {
        // --- Deposition ---
        float amount = hmU.Kd * (s - C);
        // Deposit into Regolith layer
        state.g = r + amount;
        state.a = max(0.0, s - amount);
    }
    else {
        // --- Erosion (Hybrid) ---
        float amount = hmU.Ks * (C - s); // Desired erosion amount
        amount = min(amount, d); // Can't erode more than there is water force (optional stability check)

        // Try to erode Regolith first
        if (r >= amount) {
            state.g = r - amount;
            state.a = s + amount;
        }
        else {
            // Regolith is depleted! Take what's left.
            float r_removed = r;
            state.g = 0.0;
            
            // Remaining demand attacks Bedrock
            float remainder = amount - r_removed;
            
            // Bedrock is harder (Kb)
            float b_removed = remainder * (hmU.Kb / hmU.Ks); // Scale by hardness ratio
            
            state.r = max(0.0, b - b_removed);
            state.a = s + r_removed + b_removed;
        }
    }

    terrainWrite.write(state, gid);
}
