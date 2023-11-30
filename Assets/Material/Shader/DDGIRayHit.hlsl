#ifndef __DDGI_RAY_HIT__
#define __DDGI_RAY_HIT__

#include "RayTracingHelp.hlsl"

#define INTERPOLATE_RAYTRACING_ATTRIBUTE(A0, A1, A2, BARYCENTRIC_COORDINATES) (A0 * BARYCENTRIC_COORDINATES.x + A1 * BARYCENTRIC_COORDINATES.y + A2 * BARYCENTRIC_COORDINATES.z)

void FetchIntersectionVertex(uint vertexIndex, out IntersectionInfo outVertex)
{
	outVertex.position = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributePosition);
	outVertex.normal = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributeNormal);
	outVertex.tangent = UnityRayTracingFetchVertexAttribute4(vertexIndex, kVertexAttributeTangent);
	outVertex.texCoord0 = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord0);
}

void GetCurrentIntersection(AttributeData attributeData, out IntersectionInfo intersection)
{
	// Fetch the indices of the current triangle
	uint3 triangleIndices = UnityRayTracingFetchTriangleIndices(PrimitiveIndex());

	// Fetch the 3 vertices
	IntersectionInfo v0, v1, v2;
	FetchIntersectionVertex(triangleIndices.x, v0);
	FetchIntersectionVertex(triangleIndices.y, v1);
	FetchIntersectionVertex(triangleIndices.z, v2);

	// Compute the full barycentric coordinates
	float3 barycentricCoordinates = float3(1.0 - attributeData.barycentrics.x - attributeData.barycentrics.y, attributeData.barycentrics.x, attributeData.barycentrics.y);

	//// Interpolate all the data
	intersection.position = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.position, v1.position, v2.position, barycentricCoordinates);
	intersection.normal = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.normal, v1.normal, v2.normal, barycentricCoordinates);
	intersection.tangent = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.tangent, v1.tangent, v2.tangent, barycentricCoordinates);
	intersection.texCoord0 = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.texCoord0, v1.texCoord0, v2.texCoord0, barycentricCoordinates);

	// Compute the lambda value (area computed in world space)
	v0.position = mul(ObjectToWorld3x4(), v0.position);
	v1.position = mul(ObjectToWorld3x4(), v1.position);
	v2.position = mul(ObjectToWorld3x4(), v2.position);

	intersection.triangleAreaWS = length(cross(v1.position - v0.position, v2.position - v0.position));
	intersection.texCoord0Area = abs((v1.texCoord0.x - v0.texCoord0.x) * (v2.texCoord0.y - v0.texCoord0.y) - (v2.texCoord0.x - v0.texCoord0.x) * (v1.texCoord0.y - v0.texCoord0.y));
}

Varyings initLitForwardVertexStruct(IntersectionInfo intersection)
{
	float3x3 objectToWorld = (float3x3)ObjectToWorld3x4();
	float3 viewDirWS = -WorldRayDirection();
	float3 positionWS = mul(ObjectToWorld3x4(), float4(intersection.position, 1));
	float3 normalWS = normalize(mul(objectToWorld, intersection.normal));
	half4 tangentWS = half4(normalize(mul(objectToWorld, intersection.tangent.xyz)), intersection.tangent.w);
	float2 uv0 = intersection.texCoord0;

	Varyings result = (Varyings)0;

	result.uv = TRANSFORM_TEX(uv0, _BaseMap);//uv0;

#if defined(REQUIRES_WORLD_SPACE_POS_INTERPOLATOR)
	result.positionWS = positionWS;
#endif

	result.normalWS = normalWS;

#if defined(REQUIRES_WORLD_SPACE_TANGENT_INTERPOLATOR)
	result.tangentWS = tangentWS;
#endif

	result.viewDirWS = viewDirWS;

	return result;
}

//----------------Sample Texture For Raytracing----------------
half4 SampleAlbedoAlpha(float2 uv, TEXTURE2D_PARAM(albedoAlphaMap, sampler_albedoAlphaMap))
{
	return half4(SAMPLE_TEXTURE2D_LOD(albedoAlphaMap, sampler_albedoAlphaMap, uv, 0));
}

half3 SampleNormal(float2 uv, TEXTURE2D_PARAM(bumpMap, sampler_bumpMap), half scale = half(1.0))
{
#ifdef _NORMALMAP
	half4 n = SAMPLE_TEXTURE2D_LOD(bumpMap, sampler_bumpMap, uv, 0);
#if BUMP_SCALE_NOT_SUPPORTED
	return UnpackNormal(n);
#else
	return UnpackNormalScale(n, scale);
#endif
#else
	return half3(0.0h, 0.0h, 1.0h);
#endif
}

//----------------Sample Texture For Raytracing----------------

void InitializeStandardLitSurfaceData(float2 uv, out SurfaceData outSurfaceData)
{
	half4 albedoAlpha = SampleAlbedoAlpha(uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap));
	outSurfaceData.alpha = albedoAlpha.a * _BaseColor.a;
	outSurfaceData.albedo = albedoAlpha.rgb * _BaseColor.rgb;
	outSurfaceData.normalTS = SampleNormal(uv, TEXTURE2D_ARGS(_BumpMap, sampler_BumpMap), _BumpScale);
}

void InitializeInputData(Varyings input, half3 normalTS, out InputData inputData)
{
	inputData = (InputData)0;

#if defined(REQUIRES_WORLD_SPACE_POS_INTERPOLATOR)
	inputData.positionWS = input.positionWS;
#endif

	half3 viewDirWS = input.viewDirWS;
#if defined(_NORMALMAP) || defined(_DETAIL)
	float sgn = input.tangentWS.w;;      // should be either +1 or -1
	float3 bitangent = sgn * cross(input.normalWS.xyz, input.tangentWS.xyz);
	half3x3 tangentToWorld = half3x3(input.tangentWS.xyz, bitangent.xyz, input.normalWS.xyz);

#if defined(_NORMALMAP)
	inputData.tangentToWorld = tangentToWorld;
#endif
	inputData.normalWS = TransformTangentToWorld(normalTS, tangentToWorld);
#else
	inputData.normalWS = input.normalWS;
#endif

	inputData.normalWS = NormalizeNormalPerPixel(inputData.normalWS);
	inputData.viewDirectionWS = viewDirWS;

}

[shader("closesthit")]
void ClosestHitMain(inout RayPayload payload : SV_RayPayload, AttributeData attribs : SV_IntersectionAttributes)
{
    IntersectionInfo intersection;
	GetCurrentIntersection(attribs, intersection);

	Varyings input = initLitForwardVertexStruct(intersection);

	SurfaceData surfaceData;
	InitializeStandardLitSurfaceData(input.uv, surfaceData);

	InputData inputData;
	InitializeInputData(input, surfaceData.normalTS, inputData);

	payload.albedo = surfaceData.albedo;
	payload.opacity = surfaceData.alpha;
	payload.worldPosition = inputData.positionWS;
	payload.normal = input.normalWS;
	payload.shadingNormal = inputData.normalWS;
	payload.hitT = RayTCurrent();
	payload.hitKind = HitKind();
}


#endif