//
//  SwiftBridging.h
//  from-scratch
//
//  Created by Colin Marmond on 02/02/2026.
//

#ifndef from_scratch_Bridging_Header_h
#define from_scratch_Bridging_Header_h
#include <simd/simd.h>

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

#endif
