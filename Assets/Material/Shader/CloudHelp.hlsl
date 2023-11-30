#ifndef __CLOUD_HELP__
#define __CLOUD_HELP__

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "AtmosphericHelp.hlsl"
#define kMsCount 2

TEXTURE3D(_BaseNoiseTex);
SAMPLER(sampler_BaseNoiseTex);
TEXTURE3D(_DetailNoiseTex);
SAMPLER(sampler_DetailNoiseTex);
TEXTURE2D(_WeatherTex);
SAMPLER(sampler_WeatherTex);

CBUFFER_START(UnityPerMaterial)
float _CloudAreaStart;
float _CloudAreaThickness;
float _CloudCoverage;
float _CloudDensity;
float4 _CloudWeatherUVScale;
float _CloudBasicNoiseScale;
float _CloudDetailNoiseScale;
float _BlueNoiseScale;
float4 _WindDirection;
float _WindSpeed;
float2 _BlueNoiseTexUV;

float _CloudPhaseForward;
float _CloudPhaseBackward;
float _CloudPhaseMixFactor;
float _SunLightScale;
float _AmbientLightScale;
float _GroundLightScale;
float _CloudMultiScatterExtinction;
float _CloudMultiScatterScatter;
float _CloudPowderScale;
float _CloudPowderPow;
float4 _CloudAlbedo;
float _CloudFogFade;

float _StartMaxDistance;
float _LightStepMul;
float _LightBasicStep;
float _LightingMarchMax;
float _ShapeMarchLength;
float _ShapeMarchMax;
CBUFFER_END

//采样云时所用到的信息
struct SamplingInfo
{    
    float cloudHeightMin;
    float cloudHeightMax;
    float cloudCoverage;
    float cloudDensity;
    float2 cloudWeatherUVScale;
    float cloudBasicNoiseScale;
    float cloudDetailNoiseScale;
    float3 windDirection;
    float windSpeed;
    float3 sphereCenter;            //地球中心坐标
    float earthRadius;              //地球半径
};

//多重散射的非物理近似
struct ParticipatingMediaPhase
{
    float phase[kMsCount];
};

struct ParticipatingMediaTransmittance
{
    float transmittanceToLight[kMsCount];
};

//y是穿过的距离，不是第二个解！
//这里简化求根公式需要rayDir是单位向量
//dot(x,y) != x^2 * y^2
//射线与球体相交, x 到球体最近的距离， y 穿过球体的距离
//原理是将射线方程(x = o + dl)带入球面方程求解(|x - c|^2 = r^2)
float2 RaySphereDst(float3 sphereCenter, float sphereRadius, float3 pos, float3 rayDir)
{
    float3 oc = pos - sphereCenter;
    float b = dot(rayDir, oc);
    float c = dot(oc, oc) - sphereRadius * sphereRadius;
    float t = b * b - c;//t > 0有两个交点, = 0 相切， < 0 不相交
    
    float delta = sqrt(max(t, 0));
    float dstToSphere = max(-b - delta, 0);
    float dstInSphere = max(-b + delta - dstToSphere, 0);
    return float2(dstToSphere, dstInSphere);
}


//射线与云层相交, x到云层的最近距离, y穿过云层的距离
//通过两个射线与球体相交进行计算
float2 RayCloudLayerDst(float3 sphereCenter, float earthRadius, float heightMin, float heightMax, float3 pos, float3 rayDir, bool isShape = true)
{
    float2 cloudDstMin = RaySphereDst(sphereCenter, heightMin + earthRadius, pos, rayDir);
    float2 cloudDstMax = RaySphereDst(sphereCenter, heightMax + earthRadius, pos, rayDir);
    
    //射线到云层的最近距离
    float dstToCloudLayer = 0;
    //射线穿过云层的距离
    float dstInCloudLayer = 0;
    
    //形状步进时计算相交
    if (isShape)
    {
        //在地表上
        if (pos.y <= heightMin)
        {
            float3 startPos = pos + rayDir * cloudDstMin.y;
            //开始位置在地平线以上时，设置距离
            if (startPos.y >= 0)
            {
                dstToCloudLayer = cloudDstMin.y;
                dstInCloudLayer = cloudDstMax.y - cloudDstMin.y;
            }
            return float2(dstToCloudLayer, dstInCloudLayer);
        }
        
        //在云层内
        if (pos.y > heightMin && pos.y <= heightMax)
        {
            dstToCloudLayer = 0;
            dstInCloudLayer = cloudDstMin.y > 0 ? cloudDstMin.x: cloudDstMax.y;
            return float2(dstToCloudLayer, dstInCloudLayer);
        }
        
        //在云层外
        dstToCloudLayer = cloudDstMax.x;
        dstInCloudLayer = cloudDstMin.y > 0 ? cloudDstMin.x - dstToCloudLayer: cloudDstMax.y;
    }
    else//光照步进时，步进开始点一定在云层内
    {
        dstToCloudLayer = 0;
        dstInCloudLayer = cloudDstMin.y > 0 ? cloudDstMin.x: cloudDstMax.y;
    }
    
    return float2(dstToCloudLayer, dstInCloudLayer);
}

SamplingInfo GetSampleInfo(float earthRadius)
{
    SamplingInfo dsi;

    dsi.cloudHeightMin = _CloudAreaStart;
    dsi.cloudHeightMax = _CloudAreaStart + _CloudAreaThickness;
    dsi.cloudCoverage = _CloudCoverage;
    dsi.cloudDensity = _CloudDensity;
    dsi.cloudWeatherUVScale = _CloudWeatherUVScale.xy;
    dsi.cloudBasicNoiseScale = _CloudBasicNoiseScale;
    dsi.cloudDetailNoiseScale = _CloudDetailNoiseScale;
    dsi.windDirection = _WindDirection.xyz;
    dsi.windSpeed = _WindSpeed;
    
    dsi.sphereCenter = float3(0, -earthRadius, 0);
    dsi.earthRadius = earthRadius;

    return dsi;
}

//获取高度比率，范围[0,1]，0靠近云层底部，1靠近云层顶部
float GetHeightFraction(float3 sphereCenter, float earthRadius, float3 pos, float height_min, float height_max)
{
    float height = length(pos - sphereCenter) - earthRadius;
    return(height - height_min) / (height_max - height_min);
}

//重映射
float Remap(float original_value, float original_min, float original_max, float new_min, float new_max)
{
    return new_min + saturate((original_value - original_min) / (original_max - original_min)) * (new_max - new_min);
}

float SampleCloudDensity(float3 samplePos, SamplingInfo dsi)
{
    float normalizeHeight = GetHeightFraction(dsi.sphereCenter, dsi.earthRadius, samplePos, dsi.cloudHeightMin, dsi.cloudHeightMax);

    float3 windOffset = (dsi.windDirection + float3(0.0, 0.1, 0.0)) * _Time.y * dsi.windSpeed;
    float2 sampleUV = (samplePos.xz * 0.001 + windOffset.xz * 0.001) * dsi.cloudWeatherUVScale;
    float4 weatherValue = _WeatherTex.Sample(sampler_WeatherTex, sampleUV);

    float coverage = saturate(dsi.cloudCoverage * weatherValue.x);
    float gradienShape = Remap(normalizeHeight, 0.0, 0.10, 0.1, 1.0) * Remap(normalizeHeight, 0.1, 0.8, 1.0, 0.2);

    float basicNoise = _BaseNoiseTex.Sample(sampler_BaseNoiseTex, (samplePos * 0.001 + windOffset) * dsi.cloudBasicNoiseScale).r;
    float basicCloudNoise = gradienShape * basicNoise;

    float basicCloudWithCoverage = coverage * Remap(basicCloudNoise, 1.0 - coverage, 1, 0, 1);

    float3 sampleDetailNoise = samplePos * 0.001 - windOffset * 0.15 + float3(basicNoise, 0.0, basicCloudNoise) * normalizeHeight;
    float detailNoiseComposite = _DetailNoiseTex.Sample(sampler_DetailNoiseTex, sampleDetailNoise * dsi.cloudDetailNoiseScale).r;
    float detailNoiseMixByHeight = 0.2 * lerp(detailNoiseComposite, 1 - detailNoiseComposite, saturate(normalizeHeight * 10.0));

    float densityShape = saturate(0.01 + normalizeHeight * 1.15) * dsi.cloudDensity *
        Remap(normalizeHeight, 0.0, 0.1, 0.0, 1.0) *
        Remap(normalizeHeight, 0.8, 1.0, 1.0, 0.0);


    float cloudDensity = Remap(basicCloudWithCoverage, detailNoiseMixByHeight, 1.0, 0.0, 1.0);


    return cloudDensity * densityShape;
}

ParticipatingMediaTransmittance CloudTransmittance(float3 samplePos, float3 lightDir, SamplingInfo dsi)
{
    ParticipatingMediaTransmittance participatingMediaTransmittance;
    int ms = 0;
    float extinctionAccumulation[kMsCount] = { 0,0 };
    float extinctionCoefficients[kMsCount] = { 0,0 };

    float lightMarchLength = _LightBasicStep;
    float dst = lightMarchLength * 0.5;
    
    [unroll(50)]
    for (int lightMarchNumber = 0; lightMarchNumber < _LightingMarchMax; lightMarchNumber++)
    {
        float3 currentPos = samplePos + dst * lightDir;
        float opticalDepth = SampleCloudDensity(currentPos, dsi) * lightMarchLength;
        
        extinctionCoefficients[0] = opticalDepth;
        extinctionAccumulation[0] += extinctionCoefficients[0];

        float MsExtinctionFactor = _CloudMultiScatterExtinction;
        [unroll(kMsCount)]
        for (ms = 1; ms < kMsCount; ms++)
        {
            extinctionCoefficients[ms] = extinctionCoefficients[ms - 1] * MsExtinctionFactor;
            MsExtinctionFactor *= MsExtinctionFactor;

            extinctionAccumulation[ms] += extinctionCoefficients[ms];
        }

        dst += lightMarchLength;
        lightMarchLength *= _LightStepMul;
    }
    [unroll(kMsCount)]
    for (ms = 0; ms < kMsCount; ms++)
    {
        participatingMediaTransmittance.transmittanceToLight[ms] = exp(-extinctionAccumulation[ms]);
    }

    return participatingMediaTransmittance;
}

// See http://www.pbr-book.org/3ed-2018/Volume_Scattering/Phase_Functions.html
float HGPhase(float g, float cosTheta)
{
    float numer = 1.0f - g * g;
    float denom = 1.0f + g * g + 2.0f * g * cosTheta;
    return numer / (4.0f * PI * denom * sqrt(denom));
}

float DualLobPhase(float g0, float g1, float w, float cosTheta)
{
    return lerp(HGPhase(g0, cosTheta), HGPhase(g1, cosTheta), w);
}

float GetUniformPhase()
{
    return 1.0f / (4.0f * PI);
}

ParticipatingMediaPhase GetParticipatingMediaPhase(float basePhase, float baseMsPhaseFactor)
{
    ParticipatingMediaPhase participatingMediaPhase;
    participatingMediaPhase.phase[0] = basePhase;

    const float uniformPhase = GetUniformPhase();
    float MsPhaseFactor = baseMsPhaseFactor;
    [unroll]
    for (int ms = 1; ms < kMsCount; ms++)
    {
        participatingMediaPhase.phase[ms] = lerp(uniformPhase, participatingMediaPhase.phase[0], MsPhaseFactor);
        MsPhaseFactor *= MsPhaseFactor;
    }

    return participatingMediaPhase;
}

float3 GetGroundContribution(
    float3 pos,
    float3 sunDirection,
    float3 sunIlluminance,
    float3 atmosphereTransmittanceToLight,
    float3 groundAlbedo,
    SamplingInfo dsi)
{
    //向下RayMarch地面的环境光贡献
    const float3 groundScatterDirection = float3(0.0, -1.0, 0.0); 
    //假设云的表面法线是向上
    const float3 planetSurfaceNormal = float3(0.0, 1.0, 0.0);
    // Lambert BRDF diffuse shading
    const float3 groundBrdfNdotL = saturate(dot(sunDirection, planetSurfaceNormal)) * (groundAlbedo / PI);
    const float uniformPhase = GetUniformPhase();
    //半球面
    const float groundHemisphereLuminanceIsotropic = (2.0f * PI) * uniformPhase;
    const float3 groundToCloudTransfertIsoScatter = groundBrdfNdotL * groundHemisphereLuminanceIsotropic;
    const float posNormalizeHeight = GetHeightFraction(dsi.sphereCenter, dsi.earthRadius, pos, dsi.cloudHeightMin, dsi.cloudHeightMax);
    //距离云层底部的距离
    float cloudSampleHeightToBottom = posNormalizeHeight * _CloudAreaThickness; 

    float opticalDepth = 0.0;

    const float contributionStepLength = min(4000.0, cloudSampleHeightToBottom);

    //地面贡献的环境光穿过云层会有外散射损失
    const uint sampleCount = 3;
    const float sampleSegmentT = 0.5f;
    [unroll(3)]
    for (uint s = 0; s < sampleCount; s++)
    {
        //每次采样在t处也就是t0和t1的中点，但积分距离是delta
        float t0 = float(s) / float(sampleCount);
        float t1 = float(s + 1.0) / float(sampleCount);

        t0 = t0 * t0;
        t1 = t1 * t1;

        float delta = t1 - t0; 	
        float t = t0 + (t1 - t0) * sampleSegmentT; 

        float contributionSampleT = contributionStepLength * t;
        float3 samplePos = pos + groundScatterDirection * contributionSampleT;
 
        float stepCloudDensity = SampleCloudDensity(samplePos, dsi);

        opticalDepth += stepCloudDensity * delta;
    }

    const float3 scatteredLuminance = atmosphereTransmittanceToLight * sunIlluminance * groundToCloudTransfertIsoScatter;
    return scatteredLuminance * exp(-opticalDepth * contributionStepLength);
}

#endif