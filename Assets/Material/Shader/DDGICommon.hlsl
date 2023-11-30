#ifndef __DDGI_COMMON__
#define __DDGI_COMMON__

static const float RTXGI_PI = 3.1415926535897932f;
static const float RTXGI_2PI = 6.2831853071795864f;

/**
 * Computes a low discrepancy spherically distributed direction on the unit sphere,
 * for the given index in a set of samples. Each direction is unique in
 * the set, but the set of directions is always the same.
 */
float3 RTXGISphericalFibonacci(float sampleIndex, float numSamples)
{
    const float b = (sqrt(5.f) * 0.5f + 0.5f) - 1.f;
    float phi = RTXGI_2PI * frac(sampleIndex * b);
    float cosTheta = 1.f - (2.f * sampleIndex + 1.f) * (1.f / numSamples);
    float sinTheta = sqrt(saturate(1.f - (cosTheta * cosTheta)));

    return float3((cos(phi) * sinTheta), (sin(phi) * sinTheta), cosTheta);
}

/**
 * Rotate vector v with quaternion q.
 */
float3 RTXGIQuaternionRotate(float3 v, float4 q)
{
    float3 b = q.xyz;
    float b2 = dot(b, b);
    return (v * (q.w * q.w - b2) + b * (dot(v, b) * 2.f) + cross(b, v) * (q.w * 2.f));
}

/**
 * Quaternion conjugate.
 * For unit quaternions, conjugate equals inverse.
 * Use this to create a quaternion that rotates in the opposite direction.
 */
float4 RTXGIQuaternionConjugate(float4 q)
{
    return float4(-q.xyz, q.w);
}

/**
 * Returns either -1 or 1 based on the sign of the input value.
 * If the input is zero, 1 is returned.
 */
float RTXGISignNotZero(float v)
{
    return (v >= 0.f) ? 1.f : -1.f;
}

/**
 * 2-component version of RTXGISignNotZero.
 */
float2 RTXGISignNotZero(float2 v)
{
    return float2(RTXGISignNotZero(v.x), RTXGISignNotZero(v.y));
}

//获得Probe的Grid空间位置
int3 DDGIGetProbeCoords(int probeIndex, int3 probeCount)
{
    int3 probeCoords;

    probeCoords.x = probeIndex % probeCount.x;
    probeCoords.y = probeIndex / (probeCount.x * probeCount.z);
    probeCoords.z = (probeIndex / probeCount.x) % probeCount.z;

    return probeCoords;
}

//获得Probe的全局索引
int DDGIGetProbeIndex(int3 probeCoords, int3 probeCount)
{
    int probesPerPlane = probeCount.x * probeCount.z;
    int planeIndex = probeCoords.y;
    int probeIndexInPlane = probeCoords.x + (probeCount.x * probeCoords.z);

    return (planeIndex * probesPerPlane) + probeIndexInPlane;
}

//获得Probe的世界空间位置
float3 DDGIGetProbeWorldPosition(int3 probeCoords, int3 probeCounts, float3 probeSpacing, float3 origin)
{
    float3 probeGridWorldPosition = probeCoords * probeSpacing;
    float3 probeGridShift = (probeSpacing * (probeCounts - 1)) * 0.5f;
    float3 probeWorldPosition = (probeGridWorldPosition - probeGridShift);
    
    probeWorldPosition += origin;

    return probeWorldPosition;
}

//获得指定rayIndex和probeIndex在RayDataTex下的纹理坐标
uint3 DDGIGetRayDataTexelCoords(int rayIndex, int probeIndex, int3 probeCount)
{
    int probesPerPlane = probeCount.x * probeCount.z;

    uint3 coords;
    coords.x = rayIndex;
    coords.z = probeIndex / probesPerPlane;
    coords.y = probeIndex - (coords.z * probesPerPlane);

    return coords;
}

//获得指定probeIndex和octantCoordinates在Irradiance/Distance八面体纹理集下的纹理坐标
float3 DDGIGetProbeUV(int probeIndex, float2 octantCoordinates, int numProbeInteriorTexels, int3 probeCounts)
{
    int planeIndex = int(probeIndex / (probeCounts.x * probeCounts.z));
    uint3 coords = uint3(probeIndex % probeCounts.x, (probeIndex / probeCounts.x) % probeCounts.z, planeIndex);

    // Add the border texels to get the total texels per probe
    float numProbeTexels = (numProbeInteriorTexels + 2.f);

    float textureWidth = numProbeTexels * probeCounts.x;
    float textureHeight = numProbeTexels * probeCounts.z;

    //移动到八面体纹理区域的中心，因为octantCoordinates是[-1,1]
    float2 uv = float2(coords.x * numProbeTexels, coords.y * numProbeTexels) + (numProbeTexels * 0.5f);
    //八面体纹理映射是不包括边界部分的，边界部分只用于双线性插值计算
    uv += octantCoordinates.xy * ((float)numProbeInteriorTexels * 0.5f);
    uv /= float2(textureWidth, textureHeight);
    return float3(uv, coords.z);
}

//根据SphericalFibonacci分布和随机四元数获得随机光线方向
float3 DDGIGetProbeRayDirection(int rayIndex, int probeNumRays, float4 probeRayRotation)
{
    int sampleIndex = rayIndex;

    // Get a ray direction on the sphere
    float3 direction = RTXGISphericalFibonacci(sampleIndex, probeNumRays);

    // Apply a random rotation and normalize the direction
    return normalize(RTXGIQuaternionRotate(direction, RTXGIQuaternionConjugate(probeRayRotation)));
}

//根据八面体纹理集的纹理坐标得到对应的Probe索引
int DDGIGetProbeIndex(uint3 texCoords, int probeNumTexels, int3 probeCount)
{
    int probesPerPlane = probeCount.x * probeCount.z;
    //C#端Dispatch的参数是
    //texCoords.x = probeCount.x * probeNumTexels
    //texCoords.y = probeCount.y * probeNumTexels
    int probeIndexInPlane = int(texCoords.x / probeNumTexels) + (probeCount.x * int(texCoords.y / probeNumTexels));

    return (texCoords.z * probesPerPlane) + probeIndexInPlane;
}

//从不包含边界的映射纹理坐标转换到归一化的八面体纹理坐标(-1,1)
//numTexels是不包含边界的纹理长宽
float2 DDGIGetNormalizedOctahedralCoordinates(int2 texCoords, int numTexels)
{
    // Map 2D texture coordinates to a normalized octahedral space
    float2 octahedralTexelCoord = float2(texCoords.x % numTexels, texCoords.y % numTexels);

    // Move to the center of a texel
    octahedralTexelCoord.xy += 0.5f;

    // Normalize
    octahedralTexelCoord.xy /= float(numTexels);

    // Shift to [-1, 1);
    octahedralTexelCoord *= 2.f;
    octahedralTexelCoord -= float2(1.f, 1.f);

    return octahedralTexelCoord;
}

//根据归一化八面体纹理坐标得到八面体的三维方向
float3 DDGIGetOctahedralDirection(float2 coords)
{
    //单位八面体的定义是|x|+|y|+|z|=1
    float3 direction = float3(coords.x, coords.y, 1.f - abs(coords.x) - abs(coords.y));
    //八面体下半部分的区域折叠到正方形的外围，此时三维坐标系的原点被映射到正方形的四个顶点上(上半部分的三维原点恰好就是正方形中心)
    if (direction.z < 0.f)
    {
        direction.xy = (1.f - abs(direction.yx)) * RTXGISignNotZero(direction.xy);
    }
    return normalize(direction);
}

//根据单位球面上某一方向得到对应八面体的映射坐标
float2 DDGIGetOctahedralCoordinates(float3 direction)
{
    float l1norm = abs(direction.x) + abs(direction.y) + abs(direction.z);
    //单位八面体的定义是|x|+|y|+|z|=1
    float2 uv = direction.xy * (1.f / l1norm);
    //八面体下半部分的区域折叠到正方形的外围
    //此时三维坐标系的原点被映射到正方形的四个顶点上
    //上半部分的三维原点恰好就是正方形中心
    if (direction.z < 0.f)
    {
        uv = (1.f - abs(uv.yx)) * RTXGISignNotZero(uv.xy);
    }
    return uv;
}

//Volume内部权重都是1，外部逐渐递减到0
float DDGIGetVolumeBlendWeight(float3 worldPosition, float3 origin, int3 probeCounts, float3 probeSpacing)
{
    // Get the volume's extent
    float3 extent = (probeSpacing * (probeCounts - 1)) * 0.5f;

    // Get the delta between the (rotated volume) and the world-space position
    float3 position = (worldPosition - origin);
    

    float3 delta = position - extent;
    if (all(delta < 0)) return 1.f;

    // Adjust the blend weight for each axis
    float volumeBlendWeight = 1.f;
    volumeBlendWeight *= (1.f - saturate(delta.x / probeSpacing.x));
    volumeBlendWeight *= (1.f - saturate(delta.y / probeSpacing.y));
    volumeBlendWeight *= (1.f - saturate(delta.z / probeSpacing.z));

    return volumeBlendWeight;
}

//根据世界坐标得到最近的Grid的BaseProbe
int3 DDGIGetBaseProbeGridCoords(float3 worldPosition, float3 origin, int3 probeCounts, float3 probeSpacing)
{
    // Get the vector from the volume origin to the surface point
    float3 position = worldPosition - origin;

    // Shift from [-n/2, n/2] to [0, n] (grid space)
    position += (probeSpacing * (probeCounts - 1)) * 0.5f;

    // Quantize the position to grid space
    int3 probeCoords = int3(position / probeSpacing);

    // Clamp to [0, probeCounts - 1]
    probeCoords = clamp(probeCoords, int3(0, 0, 0), (probeCounts - int3(1, 1, 1)));

    return probeCoords;
}

//根据表面法线和视角方向进行偏移
float3 DDGIGetSurfaceBias(float3 surfaceNormal, float3 cameraDirection, float probeNormalBias, float probeViewBias)
{
    return (surfaceNormal * probeNormalBias) + (-cameraDirection * probeViewBias);
}

//根据离得最近的8个Probe计算Irradiance
float3 DDGIGetVolumeIrradiance(
    float3 worldPosition,
    float3 surfaceBias,
    float3 direction,
    float3 origin,
    int3 probeCounts,
    float3 probeSpacing,
    int probeNumDistanceInteriorTexels,
    int probeNumIrradianceInteriorTexels,
    float probeIrradianceEncodingGamma,
    Texture2DArray<float4> probeDistanceTex,
    Texture2DArray<float4> probeIrradianceTex,
    SamplerState bilinearSampler
    )
{
    float3 irradiance = float3(0.f, 0.f, 0.f);
    float  accumulatedWeights = 0.f;

    
    float3 biasedWorldPosition = (worldPosition + surfaceBias);

    int3   baseProbeCoords = DDGIGetBaseProbeGridCoords(biasedWorldPosition, origin, probeCounts, probeSpacing);
    float3 baseProbeWorldPosition = DDGIGetProbeWorldPosition(baseProbeCoords, probeCounts, probeSpacing, origin);

    //用于trilinear计算
    float3 gridSpaceDistance = (biasedWorldPosition - baseProbeWorldPosition);
    float3 alpha = clamp((gridSpaceDistance / probeSpacing), float3(0.f, 0.f, 0.f), float3(1.f, 1.f, 1.f));

    for (int probeIndex = 0; probeIndex < 8; probeIndex++)
    {
        //位运算，确定ProbeCoords的Offset
        int3 adjacentProbeOffset = int3(probeIndex, probeIndex >> 1, probeIndex >> 2) & int3(1, 1, 1);
        int3 adjacentProbeCoords = clamp(baseProbeCoords + adjacentProbeOffset, int3(0, 0, 0), probeCounts - int3(1, 1, 1));
        int adjacentProbeIndex = DDGIGetProbeIndex(adjacentProbeCoords, probeCounts);
        float3 adjacentProbeWorldPosition = DDGIGetProbeWorldPosition(adjacentProbeCoords, probeCounts, probeSpacing, origin);

        float3 worldPosToAdjProbe = normalize(adjacentProbeWorldPosition - worldPosition);
        float3 biasedPosToAdjProbe = normalize(adjacentProbeWorldPosition - biasedWorldPosition);
        float  biasedPosToAdjProbeDist = length(adjacentProbeWorldPosition - biasedWorldPosition);

        float  weight = 1.f;

        //三线性插值权重
        float3 trilinear = max(0.001f, lerp(1.f - alpha, alpha, adjacentProbeOffset));
        float  trilinearWeight = (trilinear.x * trilinear.y * trilinear.z);


        //smooth backface 背对Probe的三角形也有一定非0权重
        float wrapShading = (dot(worldPosToAdjProbe, direction) + 1.f) * 0.5f;
        weight *= (wrapShading * wrapShading) + 0.2f;


        //切比雪夫可见性权重
        float2 octantCoords = DDGIGetOctahedralCoordinates(-biasedPosToAdjProbe);
        float3 probeTextureUV = DDGIGetProbeUV(adjacentProbeIndex, octantCoords, probeNumDistanceInteriorTexels, probeCounts);
        float2 filteredDistance = probeDistanceTex.SampleLevel(bilinearSampler, probeTextureUV, 0).rg;
        float variance = abs((filteredDistance.x * filteredDistance.x) - filteredDistance.y);

        float chebyshevWeight = 1.f;
        if (biasedPosToAdjProbeDist > filteredDistance.x)
        {
            float v = biasedPosToAdjProbeDist - filteredDistance.x;
            chebyshevWeight = variance / (variance + (v * v));

            chebyshevWeight = max((chebyshevWeight * chebyshevWeight * chebyshevWeight), 0.f);
        }

        weight *= max(0.05f, chebyshevWeight);
        weight = max(0.000001f, weight);
        const float crushThreshold = 0.2f;
        if (weight < crushThreshold)
        {
            weight *= (weight * weight) * (1.f / (crushThreshold * crushThreshold));
        }
        weight *= trilinearWeight;

        //获取Irradiance
        octantCoords = DDGIGetOctahedralCoordinates(direction);
        probeTextureUV = DDGIGetProbeUV(adjacentProbeIndex, octantCoords, probeNumIrradianceInteriorTexels, probeCounts);
        float3 probeIrradiance = probeIrradianceTex.SampleLevel(bilinearSampler, probeTextureUV, 0).rgb;
        
        float3 exponent = probeIrradianceEncodingGamma * 0.5f;
        probeIrradiance = pow(probeIrradiance, exponent);

        irradiance += (weight * probeIrradiance);
        accumulatedWeights += weight;
    }

    if (accumulatedWeights == 0.f) return float3(0.f, 0.f, 0.f);

    irradiance *= (1.f / accumulatedWeights);   // Normalize by the accumulated weights
    irradiance *= irradiance;                   // Go back to linear irradiance
    irradiance *= RTXGI_2PI;                    // Multiply by the area of the integration domain (hemisphere) to complete the Monte Carlo Estimator equation

    return irradiance;
}

#endif