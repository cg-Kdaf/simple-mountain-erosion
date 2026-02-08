//
//  WaterVelocity.metal
//  from-scratch
//
//  Created by Colin Marmond on 08/02/2026.
//

#include <metal_stdlib>
#include "../CommonShaders.h"
using namespace metal;

kernel void water_velocity(
    texture2d<float, access::read> terrainRead [[texture(0)]],
    texture2d<float, access::write> terrainWrite [[texture(1)]],
    texture2d<float, access::read> flux [[texture(2)]],
    texture2d<float, access::write> velocityWrite [[texture(3)]],
    constant HeightMapUniforms& hmU [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= terrainRead.get_width() || gid.y >= terrainRead.get_height()) return;

    int2 pos = int2(gid);
    
    // Outflow
    float4 fOut = flux.read(gid);
    float sumOut = fOut.x + fOut.y + fOut.z + fOut.w;

    // Inflow (Neighbor's output towards us)
    float fInL = read_tex(flux, pos + int2(-1, 0)).y; // Left neighbor's Right flux
    float fInR = read_tex(flux, pos + int2( 1, 0)).x; // Right neighbor's Left flux
    float fInT = read_tex(flux, pos + int2( 0, 1)).w; // Top neighbor's Bottom flux
    float fInB = read_tex(flux, pos + int2( 0,-1)).z; // Bottom neighbor's Top flux
    float sumIn = fInL + fInR + fInT + fInB;

    // Update Water Height
    float4 state = terrainRead.read(gid);
    float d_old = state.b;
    float volumeChange = hmU.dt * (sumIn - sumOut);
    float d_new = max(0.0, d_old + volumeChange / (hmU.l_pipe * hmU.l_pipe));
    
    state.b = d_new;
    terrainWrite.write(state, gid);

    // Calculate Velocity Vector (u, v)
    float d_avg = (d_old + d_new) * 0.5;
    float2 vel = float2(0.0);
    
    if (d_avg > 1e-4) {
        float u = (fInL - fOut.x + fOut.y - fInR) / 2.0;
        float v = (fInB - fOut.w + fOut.z - fInT) / 2.0; // Assuming Top is +Y
        // Note: Check your coordinate system. Sometimes top/bottom flux logic flips.
        // Here we assume: Top neighbor is at y+1. Flow OUT to Top is .z. Flow IN from Top is .w (bottom flux of top neighbor).
        
        vel = float2(u, v) / min(d_avg * hmU.l_pipe, 1.0); // Simple cap
    }
    
    velocityWrite.write(float4(vel.x, vel.y, 0, 0), gid);
}
