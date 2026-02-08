//
//  CommonShader.h
//  from-scratch
//
//  Created by Colin Marmond on 20/01/2026.
//

// CommonShader
#ifndef COMMONSHADERS_HEADERS
#define COMMONSHADERS_HEADERS

#include <simd/simd.h>

static inline float getWholeHeight(simd_float4 terrain) {
  return (terrain.x + terrain.y + terrain.z) / 10.0;
}

typedef struct {
  float deltaX;
  float deltaY;

  float dt;         // Time step
  float l_pipe;       // Pipe length (grid spacing)
  float gravity;
  float A_pipe;       // Pipe cross-section area

  float Kc;           // Sediment capacity constant
  float Ks;           // Dissolving constant (Regolith softness)
  float Kb;          // Dissolving constant (Bedrock hardness)
  float Kd;           // Deposition constant
  float Ke;         // Evaporation constant
} HeightMapUniforms;

typedef enum {
  Shading,
  Velocity,
  Terrain,
  Flux,
  Normal,
} TextureOverlay;

typedef struct {
  simd_float3 position;
  simd_float3 forward;
  simd_float3 right;
  simd_float3 up;
  float fovYRadians;
  float aspect;
} CameraProperties;

struct RayTracingUniforms {
  CameraProperties camera;
  float meshSize;
  
  TextureOverlay overlayDebug;
};

#endif // !COMMONSHADERS_HEADERS
