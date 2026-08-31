//
//  ShaderTypes.h
//  ipadgameapp
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#include <metal_stdlib>
using namespace metal;
typedef float2 shared_float2;
typedef float3 shared_float3;
typedef float4 shared_float4;
typedef float4x4 shared_float4x4;
typedef uint shared_uint;
#else
#include <stdint.h>
#include <simd/simd.h>
typedef vector_float2 shared_float2;
typedef vector_float3 shared_float3;
typedef vector_float4 shared_float4;
typedef matrix_float4x4 shared_float4x4;
typedef uint32_t shared_uint;
#endif

// Use standard enum types compatible with both Swift and Metal
typedef enum {
    BufferIndexParticles = 0,
    BufferIndexUniforms = 1,
    BufferIndexTrails = 2
} BufferIndex;

// Shared CPU/GPU layout types.
typedef struct {
    shared_float3 position;
    shared_float3 velocity;
    shared_float4 color;
    float life;
    float size;
} Particle;

typedef struct {
    shared_float4x4 projectionMatrix;
    shared_float4x4 viewMatrix;
    shared_uint particleCount;
    shared_uint velocityMode;
    shared_uint trailSampleCount;
    shared_uint trailsEnabled;
    float launchAngleRadians;
    float angleVarianceRadians;
    float launchSpeed;
    float velocityVariance;
    float _padding0;
    float _padding1;
    float minVelocityRange;
    float maxVelocityRange;
    float velocityWeight0;
    float velocityWeight1;
    float velocityWeight2;
    float velocityWeight3;
    float velocityWeight4;
    float velocityWeight5;
    float velocityWeight6;
    float velocityWeight7;
    float velocityWeight8;
    float velocityWeight9;
} Uniforms;

#endif /* ShaderTypes_h */
