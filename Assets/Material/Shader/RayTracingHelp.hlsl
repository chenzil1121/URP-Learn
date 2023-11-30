#ifndef __RT_HELP__
#define __RT_HELP__

#include "UnityRaytracingMeshUtils.cginc"

struct RayPayload
{
	float3  albedo;
	float   opacity;
	float3  worldPosition;
	float3  normal;
	float3  shadingNormal;
	float   hitT;
	uint    hitKind;
	// used for MipMapping based on ray cones
	float  spreadAngle;
};

struct AttributeData
{
    float2 barycentrics;
};

struct IntersectionInfo
{
	// Object space position
	float3 position;
	// Object space normn al
	float3 normal;
	// Object space tangent
	float4 tangent;
	// UV coordinates
	float2 texCoord0;
	// Value used for LOD sampling
	float  triangleAreaWS;
	float  texCoord0Area;
};

#endif