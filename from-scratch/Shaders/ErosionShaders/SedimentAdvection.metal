//
//  SedimentAdvection.metal
//  from-scratch
//
//  Created by Colin Marmond on 08/02/2026.
//

#include <metal_stdlib>
#include "../CommonShaders.h"
using namespace metal;

kernel void sediment_transport(
    texture2d<float, access::read> terrainRead [[texture(0)]],
    texture2d<float, access::write> terrainWrite [[texture(1)]],
    texture2d<float, access::read> velocity [[texture(2)]],
    constant HeightMapUniforms& hmU [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= terrainRead.get_width() || gid.y >= terrainRead.get_height()) return;

    // We only update 's' here. Copy others.
    float4 state = terrainRead.read(gid);
    
    float2 vel = velocity.read(gid).xy;
    
    // Backtrace coordinate: pos - velocity * dt
    float2 uv = (float2(gid) + 0.5); // Pixel center coordinates
    float2 back_uv = uv - vel * hmU.dt;
    
    // Manual Bilinear Interpolation for Sediment 'a' channel
    // (Metal compute doesn't support 'sample' easily without sampler setup)
    float x = back_uv.x - 0.5;
    float y = back_uv.y - 0.5;
    int x0 = int(floor(x));
    int y0 = int(floor(y));
    int x1 = x0 + 1;
    int y1 = y0 + 1;
    
    float wa = (x1 - x) * (y1 - y);
    float wb = (x1 - x) * (y - y0);
    float wc = (x - x0) * (y1 - y);
    float wd = (x - x0) * (y - y0);
    
    // Read sediment (alpha channel) from 4 neighbors
    // Note: Use clamp in read_tex logic to handle boundaries
    float s00 = read_tex(terrainRead, int2(x0, y0)).a;
    float s01 = read_tex(terrainRead, int2(x0, y1)).a;
    float s10 = read_tex(terrainRead, int2(x1, y0)).a;
    float s11 = read_tex(terrainRead, int2(x1, y1)).a;
    
    float new_s = wa*s00 + wb*s01 + wc*s10 + wd*s11;
    
    state.a = new_s;
    terrainWrite.write(state, gid);
}
