//
//  ErosionShaders.metal
//  from-scratch
//
//  Created by Colin Marmond on 19/01/2026.
//

#include <metal_stdlib>
#include "CommonShaders.h"
using namespace metal;

static float basicMountainForErosion(float2 uv) {
  float h = exp(-10.0 * pow(length(uv - float2(0.5)), 2)) / 2.0;
  float details = cos(uv.x * 10.0) + cos (uv.y * 10.0);
  float details2 = cos(uv.x * 100.0) + cos (uv.y * 100.0);
  
  return pow(h, 4.0) * 10.0 + details * 0.06 + details2 * 0.003;
}

static float getDisplacement(float2 uv) {
    return basicMountainForErosion(uv) * 1000.0;
}

kernel void reset_heightmap(
  texture2d<float, access::read_write> heightTex [[texture(0)]],
  uint2 gid [[thread_position_in_grid]])
{
  uint width = heightTex.get_width();
  uint height = heightTex.get_height();
  if (gid.x >= width || gid.y >= height) { return; }

  float2 uv = (float2(gid) + 0.5) / float2(width, height);

  float hC = getDisplacement(uv);
  heightTex.write(float4(max(0.0, hC) + 3.0, 50.0, (length(uv - float2(0.5)) < 0.1) * 0.5, 0.0), gid);
}

kernel void live_animation_heightmap(
  texture2d<float, access::read_write> heightTex [[texture(0)]],
  constant float& time [[buffer(0)]],
  uint2 gid [[thread_position_in_grid]])
{
  uint width = heightTex.get_width();
  uint height = heightTex.get_height();
  if (gid.x >= width || gid.y >= height) { return; }

  float2 uv = (float2(gid) + 0.5) / float2(width, height) + float2(time);

  // Write center height
  float hC = getDisplacement(uv);
  heightTex.write(hC, gid);
}

kernel void progressive_blur(
  texture2d<float, access::read_write> heightTex [[texture(0)]],
  uint2 gid [[thread_position_in_grid]])
{
  uint width = heightTex.get_width();
  uint height = heightTex.get_height();
  if (gid.x >= width || gid.y >= height) { return; }

  float acc = 0.0;
  acc += heightTex.read(gid + uint2(0, 1))[0];
  acc += heightTex.read(gid + uint2(1, 0))[0];
  acc += heightTex.read(gid + uint2(0, -1))[0];
  acc += heightTex.read(gid + uint2(-1, 0))[0];
  
  float ratio = 0.9;
  float new_height = heightTex.read(gid)[0] * ratio + (1.0 - ratio) * acc / 4.0;
  
  heightTex.write(new_height, gid);
}

kernel void recalculate_normals(
  texture2d<float, access::read_write> heightTex [[texture(0)]],
  texture2d<float, access::read_write> normalTex [[texture(1)]],
  constant HeightMapUniforms& hmU [[buffer(0)]],
  uint2 gid [[thread_position_in_grid]])
{
  uint w = heightTex.get_width();
  uint h = heightTex.get_height();
  if (gid.x >= w || gid.y >= h) return;

  uint2 left  = uint2(gid.x == 0 ? 0 : gid.x - 1, gid.y);
  uint2 right = uint2(min(gid.x + 1, w - 1), gid.y);
  uint2 down  = uint2(gid.x, gid.y == 0 ? 0 : gid.y - 1);
  uint2 up    = uint2(gid.x, min(gid.y + 1, h - 1));

  float hL = getWholeHeight(heightTex.read(left));
  float hR = getWholeHeight(heightTex.read(right));
  float hD = getWholeHeight(heightTex.read(down));
  float hU = getWholeHeight(heightTex.read(up));

  float dhdx = (hR - hL) * 0.5;
  float dhdy = (hU - hD) * 0.5;

  float3 N = normalize(float3(-dhdx / hmU.deltaX, 1.0, -dhdy / hmU.deltaY));
  normalTex.write(float4(N, 1.0), gid);
}

// Helper to get boundary-safe values
inline float4 read_tex(texture2d<float, access::read> tex, int2 pos) {
    uint w = tex.get_width();
    uint h = tex.get_height();
    pos = clamp(pos, int2(0), int2(w - 1, h - 1));
    return tex.read(uint2(pos));
}

// =================================================================================
// 1. ADD WATER SOURCES (Rain)
// =================================================================================
kernel void add_rain(
    texture2d<float, access::read> terrainRead [[texture(0)]],
    texture2d<float, access::write> terrainWrite [[texture(1)]],
    constant HeightMapUniforms& hmU [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= terrainRead.get_width() || gid.y >= terrainRead.get_height()) return;

    float4 state = terrainRead.read(gid);
    // R=Bedrock, G=Regolith, B=Water, A=Sediment
    
    // Add simple uniform rain. In a real app, use a noise texture here.
    float rain_amount = 0.0;
    
    state.b += rain_amount * hmU.dt;
    
    terrainWrite.write(state, gid);
}

// =================================================================================
// 2. FLUX CALCULATION (Shallow Water Pipe Model)
// =================================================================================
kernel void calc_flux(
    texture2d<float, access::read> terrain [[texture(0)]],
    texture2d<float, access::read> fluxRead [[texture(1)]],
    texture2d<float, access::write> fluxWrite [[texture(2)]],
    constant HeightMapUniforms& hmU [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= terrain.get_width() || gid.y >= terrain.get_height()) return;

    int2 pos = int2(gid);
    
    // Height = Bedrock(r) + Regolith(g) + Water(b)
    float4 cell = terrain.read(gid);
    float h = cell.r + cell.g + cell.b;

    // Neighbors
  float4 terrainL = read_tex(terrain, pos + int2(-1, 0));
  float hL = terrainL.r + terrainL.g + terrainL.b;
  float4 terrainR = read_tex(terrain, pos + int2( 1, 0));
  float hR = terrainR.r + terrainR.g + terrainR.b;
  float4 terrainT = read_tex(terrain, pos + int2( 0, 1));
  float hT = terrainT.r + terrainT.g + terrainT.b;
  float4 terrainB = read_tex(terrain, pos + int2( 0,-1));
  float hB = terrainB.r + terrainB.g + terrainB.b;

    // Current Flux (Left, Right, Top, Bottom)
    float4 f = fluxRead.read(gid);

    // Update Fluxes
    // f_new = max(0, f_old + dt * A * (g * deltaH) / l)
    f.x = max(0.0, f.x + hmU.dt * hmU.A_pipe * (hmU.gravity * (h - hL)) / hmU.l_pipe); // Left
    f.y = max(0.0, f.y + hmU.dt * hmU.A_pipe * (hmU.gravity * (h - hR)) / hmU.l_pipe); // Right
    f.z = max(0.0, f.z + hmU.dt * hmU.A_pipe * (hmU.gravity * (h - hT)) / hmU.l_pipe); // Top
    f.w = max(0.0, f.w + hmU.dt * hmU.A_pipe * (hmU.gravity * (h - hB)) / hmU.l_pipe); // Bottom

    // Scaling to prevent negative water
    float totalOut = f.x + f.y + f.z + f.w;
    float currentWater = cell.b;
    float K = min(1.0, (currentWater * hmU.l_pipe * hmU.l_pipe) / (totalOut * hmU.dt + 1e-5)); // 1e-5 to avoid div/0

    f *= K;

    fluxWrite.write(f, gid);
}

// =================================================================================
// 3. WATER UPDATE & VELOCITY FIELD
// =================================================================================
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

// =================================================================================
// 4. EROSION & DEPOSITION (The Hybrid Stava Model)
// =================================================================================
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

// =================================================================================
// 5. SEDIMENT ADVECTION (Moving sediment with water)
// =================================================================================
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

// =================================================================================
// 6. EVAPORATION
// =================================================================================
kernel void evaporation(
    texture2d<float, access::read> terrainRead [[texture(0)]],
    texture2d<float, access::write> terrainWrite [[texture(1)]],
    constant HeightMapUniforms& hmU [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= terrainRead.get_width() || gid.y >= terrainRead.get_height()) return;

    float4 state = terrainRead.read(gid);
    
    // Simple exponential decay
    state.b = state.b * (1.0 - hmU.Ke * hmU.dt);
    if(state.b < 0.0001) state.b = 0.0; // Cleanup threshold
    
    terrainWrite.write(state, gid);
}
