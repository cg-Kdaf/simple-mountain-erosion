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
  float Ks;           // Dissolving constant
  float Kd;           // Deposition constant
  float Ke;         // Evaporation constant
  
  float talusScale;    // Slope stability threshold
  float thermalStrength; // Thermal erosion strength
  float advectMultiplier; // Sediment advection multiplier
  float velAdvMag;    // Velocity advection magnitude
  float velMult;      // Velocity multiplier
  float mountainNoiseFrequency; // Frequency of mountain noise
} HeightMapUniforms;

typedef enum {
  Shading,
  Velocity,
  Terrain,
  Flux,
  Normal,
  Slipperage,
  Sediment,
  SlipperageFlux,
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
