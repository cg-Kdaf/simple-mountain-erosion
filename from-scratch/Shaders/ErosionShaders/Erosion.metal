//
//  Erosion.metal
//  from-scratch
//
//  Created by Colin Marmond on 16/02/2026.
//

#include <metal_stdlib>
#include "../CommonShaders.h"
using namespace metal;

constexpr sampler textureSampler (mag_filter::linear,
                                  min_filter::linear);

kernel void advection_compute(texture2d<float, access::read> velocity_in [[texture(0)]],
                              texture2d<float, access::sample> sediment_in [[texture(1)]],
                              texture2d<float, access::write> sediment_out [[texture(2)]],
                              constant HeightMapUniforms& u [[buffer(0)]],
                              uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= sediment_out.get_width() || gid.y >= sediment_out.get_height()) return;
  
  float4 curvel = velocity_in.read(gid);
  float4 useVel = curvel * u.advectMultiplier * 0.5;
  
  float2 coo = float2(gid);
  float2 oldloc = float2(coo.x - useVel.x * u.dt, coo.y - useVel.y * u.dt);
  
  float oldsedi = sediment_in.sample(textureSampler, oldloc).x;
  
  sediment_out.write(float4(oldsedi, 0.0, 0.0, 1.0), gid);
}

kernel void flow_compute(texture2d<float, access::read> terrain_in [[texture(0)]],
                         texture2d<float, access::read> flux_in [[texture(1)]],
                         texture2d<float, access::write> flux_out [[texture(2)]],
                         constant HeightMapUniforms& u [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= flux_out.get_width() || gid.y >= flux_out.get_height()) return;
  
  int2 coo = int2(gid);
  float g = 0.80;
  
  // Load neighbors (Terrain: x=height, y=water)
  float4 top    = read_tex(terrain_in, coo + int2(0, 1));
  float4 right  = read_tex(terrain_in, coo + int2(1, 0));
  float4 bottom = read_tex(terrain_in, coo + int2(0,-1));
  float4 left   = read_tex(terrain_in, coo + int2(-1,0));
  
  float damping = 1.0;
  float4 curTerrain = terrain_in.read(gid);
  float4 curFlux = flux_in.read(gid) * damping;
  
  float height_water = curTerrain.y + curTerrain.x;
  
  // Hydrostatic pressure differences
  float Htopout    = height_water - (top.y + top.x);
  float Hrightout  = height_water - (right.y + right.x);
  float Hbottomout = height_water - (bottom.x + bottom.y); // Note: bottom.x + bottom.y order swap in GLSL
  float Hleftout   = height_water - (left.y + left.x);
  
  float constant_val = u.dt * g * u.A_pipe / u.l_pipe;
  
  // Flux Map R: left, G: right, B: top, A: bottom
  float fleftout   = max(0.0, curFlux.x + constant_val * Hleftout);
  float frightout  = max(0.0, curFlux.y + constant_val * Hrightout);
  float ftopout    = max(0.0, curFlux.z + constant_val * Htopout);
  float fbottomout = max(0.0, curFlux.w + constant_val * Hbottomout);
  
  float waterOut = u.dt * (fleftout + frightout + ftopout + fbottomout);
  
  // Scaling to prevent negative water volume
  float k = min(1.0, (curTerrain.y * u.l_pipe * u.l_pipe) / (waterOut + 1e-6)); // Added epsilon to avoid div/0
  
  fleftout   *= k;
  frightout  *= k;
  ftopout    *= k;
  fbottomout *= k;
  
  // Boundary conditions
  if (coo.x <= 1) fleftout = 0.0;
  else if (coo.x >= (int(terrain_in.get_width()) - 1)) frightout = 0.0;
  
  if (coo.y <= 1) fbottomout = 0.0;
  else if (coo.y >= (int(terrain_in.get_height()) - 1)) ftopout = 0.0;
  
  flux_out.write(float4(fleftout, frightout, ftopout, fbottomout), gid);
}

kernel void sediment_compute(texture2d<float, access::read> terrain_in [[texture(0)]],
                             texture2d<float, access::write> terrain_out [[texture(1)]],
                             texture2d<float, access::read> sediment_in [[texture(2)]],
                             texture2d<float, access::write> sediment_out [[texture(3)]],
                             texture2d<float, access::read> velocity_in [[texture(4)]],
                             texture2d<float, access::read> normal_in [[texture(5)]],
                             constant HeightMapUniforms& u [[buffer(0)]],
                             uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= terrain_out.get_width() || gid.y >= terrain_out.get_height()) return;
  
  int2 coo = int2(gid);
  float3 nor = read_tex(normal_in, coo).xyz;
  float slope = max(0.1, sqrt(1.0 - nor.y * nor.y));
  
  float4 curvel = velocity_in.read(gid);
  float4 curSediment = sediment_in.read(gid);
  float4 curTerrain = terrain_in.read(gid);
  
  float velo = length(curvel.xy);
  float sedicap = u.Kc * slope * velo;
  
  float cursedi = curSediment.x;
  float height = curTerrain.x;
  float outsedi = curSediment.x;
  
  if (sedicap > cursedi) {
    float changesedi = (sedicap - cursedi) * u.Ks;
    height -= changesedi;
    outsedi += changesedi;
  } else {
    float changesedi = (cursedi - sedicap) * u.Kd;
    height += changesedi;
    outsedi -= changesedi;
  }
  
  sediment_out.write(float4(outsedi, 0.0, 0.0, 1.0), gid);
  terrain_out.write(float4(height, curTerrain.y, curTerrain.z, curTerrain.w), gid);
}

kernel void slipperage_compute(texture2d<float, access::read> terrain_in [[texture(0)]],
                               texture2d<float, access::write> slipperage_out [[texture(1)]],
                               constant HeightMapUniforms& u [[buffer(0)]],
                               uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= slipperage_out.get_width() || gid.y >= slipperage_out.get_height()) return;
  
  int2 coo = int2(gid);
  int w = terrain_in.get_width();
  int h = terrain_in.get_height();
  
  float r = read_tex(terrain_in, coo + int2(1, 0)).x;
  float t = read_tex(terrain_in, coo + int2(0, 1)).x;
  float b = read_tex(terrain_in, coo + int2(0,-1)).x;
  float l = read_tex(terrain_in, coo + int2(-1,0)).x;
  float terraincur = terrain_in.read(gid).x;
  
  if (coo.x <= 1) l = terraincur;
  else if (coo.x >= (w - 1)) r = terraincur;
  
  if (coo.y <= 1) b = terraincur;
  else if (coo.y >= (h - 1)) t = terraincur;
  
  // The talus angle (angle of repose) - material flows when slope exceeds this
  float talusAngle = u.talusScale;
  
  // Store talus angle as slipperage threshold
  float4 slipperage = float4(talusAngle, 0.0, 0.0, 1.0);
  slipperage_out.write(slipperage, gid);
}

kernel void thermal_apply_compute(texture2d<float, access::read> terrain_in [[texture(0)]],
                                  texture2d<float, access::write> terrain_out [[texture(1)]],
                                  texture2d<float, access::read> terrain_flux_in [[texture(2)]],
                                  constant HeightMapUniforms& u [[buffer(0)]],
                                  uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= terrain_out.get_width() || gid.y >= terrain_out.get_height()) return;
  
  int2 coo = int2(gid);
  int w = int(terrain_out.get_width());
  int h = int(terrain_out.get_height());
  
  float4 topflux    = read_tex(terrain_flux_in, coo + int2(0, 1));
  float4 rightflux  = read_tex(terrain_flux_in, coo + int2(1, 0));
  float4 bottomflux = read_tex(terrain_flux_in, coo + int2(0,-1));
  float4 leftflux   = read_tex(terrain_flux_in, coo + int2(-1,0));
  
  // Flux Map: R(left), G(right), B(top), A(bottom)
  // Inflows: from top cell's bottom flux (topflux.w), from right cell's left flux (rightflux.x),
  //          from bottom cell's top flux (bottomflux.z), from left cell's right flux (leftflux.y)
  float4 curflux = terrain_flux_in.read(gid);
  
  // Apply boundary conditions - zero out inflows from out-of-bounds neighbors
  float inflow_top = (coo.y >= (h - 1)) ? 0.0 : topflux.w;
  float inflow_right = (coo.x >= (w - 1)) ? 0.0 : rightflux.x;
  float inflow_bottom = (coo.y <= 1) ? 0.0 : bottomflux.z;
  float inflow_left = (coo.x <= 1) ? 0.0 : leftflux.y;
  
  float inflow = inflow_top + inflow_right + inflow_bottom + inflow_left;
  float outflow = curflux.x + curflux.y + curflux.z + curflux.w;
  
  float vol = inflow - outflow;
  
  float tdelta = u.dt * u.thermalStrength * vol;
  float4 curTerrain = terrain_in.read(gid);
  
  float4 terrain = float4(curTerrain.x + tdelta, curTerrain.y, curTerrain.z, curTerrain.w);
  terrain_out.write(terrain, gid);
}

kernel void thermal_flux_compute(texture2d<float, access::read> terrain_in [[texture(0)]],
                                 texture2d<float, access::read> slipperage_in [[texture(1)]],
                                 texture2d<float, access::write> terrain_flux_out [[texture(2)]],
                                 constant HeightMapUniforms& u [[buffer(0)]],
                                 uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= terrain_flux_out.get_width() || gid.y >= terrain_flux_out.get_height()) return;
  
  int2 coo = int2(gid);
  
  float terraincur = terrain_in.read(gid).x;
  float talusAngle = slipperage_in.read(gid).x;
  
  // Sample all 8 neighbors
  float neighbors[8];
  int2 offsets[8] = {
    int2(-1,0), int2(1,0), int2(0,1), int2(0,-1),  // cardinal
    int2(-1,-1), int2(1,-1), int2(-1,1), int2(1,1) // diagonal
  };
  
  // Distance factors: 1.0 for cardinal directions, sqrt(2) for diagonals
  float distances[8] = {1.0, 1.0, 1.0, 1.0, 1.414, 1.414, 1.414, 1.414};
  
  // Calculate total material to move and weighted distribution
  float totalDiff = 0.0;
  float diffs[8];
  
  for (int i = 0; i < 8; i++) {
    neighbors[i] = read_tex(terrain_in, coo + offsets[i]).x;
    
    // Height difference divided by distance (slope)
    float slope = (terraincur - neighbors[i]) / distances[i];
    
    // Only move material if slope exceeds talus angle
    if (slope > talusAngle) {
      diffs[i] = (slope - talusAngle) * distances[i];
      totalDiff += diffs[i];
    } else {
      diffs[i] = 0.0;
    }
  }
  
  // Flux Map: R(left), G(right), B(top), A(bottom)
  float4 cardinalFlow = float4(0.0);
  
  if (totalDiff > 1e-5) {
    // Normalize and scale
    float maxTransfer = terraincur * 0.5; // Don't move more than half the height
    float scale = min(1.0, maxTransfer / (totalDiff + 1e-6));
    
    // Distribute to cardinal directions (sum diagonal contributions)
    cardinalFlow.x = (diffs[0] + diffs[4] * 0.5 + diffs[6] * 0.5) * scale; // left
    cardinalFlow.y = (diffs[1] + diffs[5] * 0.5 + diffs[7] * 0.5) * scale; // right
    cardinalFlow.z = (diffs[2] + diffs[6] * 0.5 + diffs[7] * 0.5) * scale; // top
    cardinalFlow.w = (diffs[3] + diffs[4] * 0.5 + diffs[5] * 0.5) * scale; // bottom
  }
  
  terrain_flux_out.write(cardinalFlow, gid);
}

kernel void waterheight_compute(texture2d<float, access::read> terrain_in [[texture(0)]],
                                texture2d<float, access::write> terrain_out [[texture(1)]],
                                texture2d<float, access::read> flux_in [[texture(2)]],
                                texture2d<float, access::read> velocity_in [[texture(3)]],
                                texture2d<float, access::write> velocity_out [[texture(4)]],
                                constant HeightMapUniforms& u [[buffer(0)]],
                                uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= terrain_out.get_width() || gid.y >= terrain_out.get_height()) return;
  
  int2 coo = int2(gid);
  uint w = terrain_in.get_width();
  uint h = terrain_in.get_height();
  
  // Flux Map R: left, G: right, B: top, A: bottom
  float4 curflux    = flux_in.read(gid);
  float4 cur        = terrain_in.read(gid);
  float4 curvel     = velocity_in.read(gid);
  
  float4 topflux    = read_tex(flux_in, coo + int2(0, 1));
  float4 rightflux  = read_tex(flux_in, coo + int2(1, 0));
  float4 bottomflux = read_tex(flux_in, coo + int2(0,-1));
  float4 leftflux   = read_tex(flux_in, coo + int2(-1,0));
  
  // Outflow
  float fleftout   = curflux.x;
  float frightout  = curflux.y;
  float ftopout    = curflux.z;
  float fbottomout = curflux.w;
  
  vec<float, 4> outputflux = curflux;
  
  float fout = fleftout + frightout + ftopout + fbottomout;
  
  // Inflow from neighbors - zero out at boundaries to prevent water creation
  float fin_top = (coo.y >= int(h - 1)) ? 0.0 : topflux.w;
  float fin_right = (coo.x >= int(w - 1)) ? 0.0 : rightflux.x;
  float fin_bottom = (coo.y <= 1) ? 0.0 : bottomflux.z;
  float fin_left = (coo.x <= 1) ? 0.0 : leftflux.y;
  
  float fin = fin_top + fin_right + fin_bottom + fin_left;
  
  float deltavol = u.dt * (fin - fout) / (u.l_pipe * u.l_pipe);
  float cur_water = cur.y;
  float d2 = max(cur_water + deltavol, 0.0);
  float da = (cur_water + d2) / 2.0;
  
  float2 veloci = float2(0.0);
  
  if ((da <= 0.0001) || (cur_water == 0.0 && deltavol == 0.0)) {
    veloci = float2(0.0);
  } else {
    // Calculate velocity based on flux differences, respecting boundaries
    float left_contrib = (coo.x <= 1) ? 0.0 : leftflux.y;
    float right_contrib = (coo.x >= int(w - 1)) ? 0.0 : rightflux.x;
    float bottom_contrib = (coo.y <= 1) ? 0.0 : bottomflux.z;
    float top_contrib = (coo.y >= int(h - 1)) ? 0.0 : topflux.w;
    
    veloci = float2(left_contrib - outputflux.x - right_contrib + outputflux.y,
                    bottom_contrib - outputflux.w - top_contrib + outputflux.z);
    veloci = veloci / (da * u.l_pipe);
  }
  
  if (cur_water < 0.01) {
    veloci = float2(0.0);
  } else {
    // Velocity advection
    float4 useVel = curvel / 2.0;
    int2 oldloc = int2(int(coo.x - useVel.x * u.dt), int(coo.y - useVel.y * u.dt));
    
    // Manual clamp for advection lookup
    oldloc = clamp(oldloc, int2(0), int2(w - 1, h - 1));
    
    float2 oldvel = velocity_in.read(uint2(oldloc)).xy;
    veloci += oldvel * u.velAdvMag;
  }
  
  float4 velocity_value = float4(veloci * u.velMult, 0.0, 1.0);
  cur_water += deltavol;
  
  if (cur_water < 0.001) {
    cur_water = 0.0;
  }
  
  float4 terrain_value = float4(cur.x, cur_water, 0.0, 1.0);
  
  velocity_out.write(velocity_value, gid);
  terrain_out.write(terrain_value, gid);
}

