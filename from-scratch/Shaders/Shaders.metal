//
//  Shaders.metal
//  from-scratch
//
//  Created by Colin Marmond on 21/12/2025.
//

#include <metal_stdlib>
using namespace metal;
using namespace raytracing;

struct Camera {
  float3 position;
  float3 forward;
  float3 right;
  float3 up;
  float fovYRadians;
  float aspect;
};

inline ray generateCameraRay(uint2 gid, uint2 viewportSize, Camera camera)
{
  // 1. Map pixel center to NDC [-1, 1]
  float2 uv = (float2(gid) + 0.5) / float2(viewportSize);
  float2 ndc = uv * 2.0 - 1.0;

  // 2. Calculate the size of the view plane based on FOV
  // tan(fov/2) gives us the height of the image plane at 1 unit distance
  float tanHalfFov = tan(camera.fovYRadians * 0.5);

  // 3. Calculate offsets on the image plane
  // Scale X by aspect ratio to prevent distortion
  float screenX = ndc.x * camera.aspect * tanHalfFov;
  
  // Invert Y because screen coordinates (Y+) usually point down,
  // while world space Up (Y+) points up.
  float screenY = -ndc.y * tanHalfFov;

  // 4. Construct direction: Forward + projected offsets on Right and Up vectors
  float3 dir = normalize(camera.forward + (camera.right * screenX) + (camera.up * screenY));

  // 5. Origin is the camera position
  float3 origin = camera.position;

  constexpr float tMin = 0.0;
  constexpr float tMax = 1e6;

  return ray(origin, dir, tMin, tMax);
}

struct Vertex {
  float3 position;
  float3 normal;
  float2 uv;
};

float getDisplacement(float2 uv) {
    return cos(uv.x * 10.0) + sin(uv.y * 10.0);
}

kernel void compute_texture(
  texture2d<float, access::read_write> heightTex [[texture(0)]],
  constant float& time [[buffer(0)]],
  uint2 gid [[thread_position_in_grid]])
{
  uint width = heightTex.get_width();
  uint height = heightTex.get_height();
  if (gid.x >= width || gid.y >= height) { return; }

  float2 uv = float2(gid) / float2(width, height);

  heightTex.write(getDisplacement(uv + float2(time)), gid);
}

kernel void compute_vertices(
    device const Vertex* inVertices [[buffer(0)]],
    device Vertex* outVertices [[buffer(1)]],
    constant uint& vertexCount [[buffer(2)]],
    texture2d<float, access::read_write> heightTex [[texture(0)]],
    uint id [[thread_position_in_grid]])
{
  if (id >= vertexCount) { return; }
  
  Vertex v = inVertices[id];
  
  float height = heightTex.read(uint2(v.uv * float2(heightTex.get_width(),
                                                    heightTex.get_height()) - float2(0.5)))[0];

  float scale = 0.2;
  outVertices[id].position.y = v.position.y + height * scale;
}

// Computes smooth per-vertex normals by averaging adjacent triangle normals on a regular grid.
// Expects:
//  - inVertices: original (pre-normal) vertices (unused here but kept for symmetry)
//  - outVertices: vertices with displaced positions to read/write normals
//  - vertexCount: total vertex count
//  - vertsPerRow, vertsPerCol: grid dimensions (row-major, vertsPerRow = segmentsX + 1)
kernel void update_normals(
    device Vertex* vertices [[buffer(0)]],
    constant uint& vertexCount [[buffer(1)]],
    constant uint& vertsPerRow [[buffer(2)]],
    constant uint& vertsPerCol [[buffer(3)]],
    uint id [[thread_position_in_grid]])
{
  if (id >= vertexCount) { return; }

  uint row = id / vertsPerRow;
  uint col = id % vertsPerRow;

  float3 accum = float3(0.0);

  // Helper to fetch displaced position from outVertices
  auto P = [&](uint r, uint c) -> float3 {
    uint idx = r * vertsPerRow + c;
    return vertices[idx].position;
  };

  // For each of up to four adjacent quads around the vertex, accumulate the two triangle normals
  // Quad to the bottom-left (r-1,c-1) .. (r,c)
  if (row > 0 && col > 0) {
    float3 p00 = P(row - 1, col - 1);
    float3 p10 = P(row - 1, col    );
    float3 p01 = P(row,     col - 1);
    float3 p11 = P(row,     col    );
    // Triangles: (p00,p10,p01) and (p01,p10,p11)
    float3 n0 = cross(p10 - p00, p01 - p00);
    float3 n1 = cross(p11 - p01, p10 - p01);
    if (n0.y < 0.0) n0 = -n0;
    if (n1.y < 0.0) n1 = -n1;
    accum += n0;
    accum += n1;
  }

  // Quad to the bottom-right (r-1,c) .. (r,c+1)
  if (row > 0 && col + 1 < vertsPerRow) {
    float3 p00 = P(row - 1, col    );
    float3 p10 = P(row - 1, col + 1);
    float3 p01 = P(row,     col    );
    float3 p11 = P(row,     col + 1);
    float3 n0 = cross(p10 - p00, p01 - p00);
    float3 n1 = cross(p11 - p01, p10 - p01);
    if (n0.y < 0.0) n0 = -n0;
    if (n1.y < 0.0) n1 = -n1;
    accum += n0;
    accum += n1;
  }

  // Quad to the top-left (r,c-1) .. (r+1,c)
  if (row + 1 < vertsPerCol && col > 0) {
    float3 p00 = P(row,     col - 1);
    float3 p10 = P(row,     col    );
    float3 p01 = P(row + 1, col - 1);
    float3 p11 = P(row + 1, col    );
    float3 n0 = cross(p10 - p00, p01 - p00);
    float3 n1 = cross(p11 - p01, p10 - p01);
    if (n0.y < 0.0) n0 = -n0;
    if (n1.y < 0.0) n1 = -n1;
    accum += n0;
    accum += n1;
  }

  // Quad to the top-right (r,c) .. (r+1,c+1)
  if (row + 1 < vertsPerCol && col + 1 < vertsPerRow) {
    float3 p00 = P(row,     col    );
    float3 p10 = P(row,     col + 1);
    float3 p01 = P(row + 1, col    );
    float3 p11 = P(row + 1, col + 1);
    float3 n0 = cross(p10 - p00, p01 - p00);
    float3 n1 = cross(p11 - p01, p10 - p01);
    if (n0.y < 0.0) n0 = -n0;
    if (n1.y < 0.0) n1 = -n1;
    accum += n0;
    accum += n1;
  }

  float3 N = (length(accum) > 0.0) ? normalize(accum) : float3(0.0, 1.0, 0.0);

  // Write back normal while preserving displaced position and uv
  Vertex v = vertices[id];
  v.normal = N;
  vertices[id] = v;
}

kernel void compute_main(texture2d<float, access::write> outTexture [[texture(0)]],
                         uint2 gid [[thread_position_in_grid]],
                         metal::raytracing::primitive_acceleration_structure accelerationStructure [[buffer(0)]],
                         device const Vertex* vertices [[buffer(1)]],
                         device const uint32_t* indices [[buffer(2)]],
                         constant Camera &camera [[buffer(3)]])
{
  uint2 size = uint2(outTexture.get_width(), outTexture.get_height());
  if (gid.x >= size.x || gid.y >= size.y) { return; }

  // Generate camera ray
  ray r = generateCameraRay(gid, size, camera);

  // Intersect with the acceleration structure
  intersector<triangle_data> intersector;
  intersection_result<triangle_data> intersection = intersector.intersect(r, accelerationStructure);

  // Default background (sky-like gradient)
  float2 uv = float2(gid) / float2(size);
  float3 color = mix(float3(0.6, 0.8, 1.0), float3(0.1, 0.2, 0.4), uv.y);

  if (intersection.distance > 0.0) {
    uint triID = intersection.primitive_id;
    uint i0 = indices[triID * 3 + 0];
    uint i1 = indices[triID * 3 + 1];
    uint i2 = indices[triID * 3 + 2];
    
    float3 n0 = vertices[i0].normal;
    float3 n1 = vertices[i1].normal;
    float3 n2 = vertices[i2].normal;
    
    float2 bc = intersection.triangle_barycentric_coord;
    float w = 1.0 - bc.x - bc.y;
    float3 N = normalize(n0 * w + n1 * bc.x + n2 * bc.y);

    // Simple Lambert shading
    float3 L = normalize(float3(0.5, 0.8, 0.6)); // fixed light direction
    float3 V = normalize(-r.direction);          // view direction

    float ambient = 0.1;
    float ndotl = max(dot(N, L), 0.0);

    // Simple albedo to make it visible
    float3 albedo = float3(0.75, 0.65, 0.55);

    // Optional: face orientation fix (avoid backface darkening if desired)
    // if (dot(N, V) < 0.0) N = -N;

    float3 shaded = albedo * (ambient + ndotl);

    // Optional: small rim light for nicer look
    float rim = pow(clamp(1.0 - max(dot(N, V), 0.0), 0.0, 1.0), 2.0) * 0.05;
    shaded += rim;

    color = clamp(shaded, 0.0, 1.0);
  }
  

  outTexture.write(float4(color, 1.0), gid);
}

