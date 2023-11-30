Shader "CZL/RayMarchingCloud"
{
    Properties
    {
        [HideInInspector] _MainTex("Texture", 2D) = "white" {}
        //纹理
        _WeatherTex("WeatherTex",2D) = "white" {}
        _BaseNoiseTex("BaseNoiseTex",3D) = "white" {}
        _DetailNoiseTex("DetailNoiseTex",3D) = "white" {}
        _BlueNoiseTex("BlueNoiseTex",2D) = "white" {}
        //云的形状
        _CloudAreaStart("CloudAreaStart",Range(4000.0,20000.0)) = 4000.0
        _CloudAreaThickness("CloudAreaThickness",Range(100.0,20000.0)) = 10000.0
        _CloudCoverage("CloudCoverage",Range(0.0,1.0)) = 0.5
        _CloudDensity("CloudDensity",Range(0.0,1.0)) = 0.1
        _CloudWeatherUVScale("CloudWeatherUVScale",Vector) = (0.005, 0.005, 0.0,0.0)
        _CloudBasicNoiseScale("CloudBasicNoiseScale",Range(0.0,1.0)) = 0.15
        _CloudDetailNoiseScale("CloudDetailNoiseScale",Range(0.0,1.0)) = 0.30
        _BlueNoiseScale("BlueNoiseScale",Range(0.0,10.0)) = 5
        _WindDirection("WindDirection",Vector) = (0.8, 0.2, 0.4,1.0)
        _WindSpeed("WindSpeed",Range(0.0,1.0)) = 0.0
        //云的光照
        _CloudPhaseForward("CloudPhaseForward",Range(0.01,0.99)) = 0.5
        _CloudPhaseBackward("CloudPhaseBackward",Range(-0.99,-0.01)) = -0.5
        _CloudPhaseMixFactor("CloudPhaseMixFactor",Range(0.01,0.99)) = 0.2
        _SunLightScale("SunLightScale",Range(0.0,1.0)) = 0.5
        _AmbientLightScale("AmbientLightScale", Range(0.0,1.0)) = 0.5
        _GroundLightScale("GroundLightScale", Range(0.0,1.0)) = 0.5
        _CloudMultiScatterExtinction("CloudMultiScatterExtinction",Range(0.0,1.0)) = 0.5
        _CloudMultiScatterScatter("CloudMultiScatterScatter",Range(0.0,1.0)) = 0.75
        _CloudPowderScale("CloudPowderScale",Range(0.01, 100.0)) = 20.0
        _CloudPowderPow("CloudPowderPow",Range(0.01, 10.0)) = 0.5
        _CloudAlbedo("CloudAlbedo",Color) = (1,1,1,1)
        _CloudFogFade("CloudFogFade",Range(1,12)) = 5
        //性能
        _StartMaxDistance("StartMaxDistance",Range(100000,500000)) = 350000
        _LightStepMul("LightStepMul",Range(1.01, 1.5)) = 1.05
        _LightBasicStep("LightBasicStep",Range(100,500)) = 167
        _LightingMarchMax("LightingMarchMax",Range(6,24)) = 16
        _ShapeMarchLength("ShapeMarchLength", Range(100,800)) = 100
        _ShapeMarchMax("ShapeMarchMax",Range(3,128)) = 90
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        ENDHLSL

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            TEXTURE2D(_CameraDepthTexture);
            SAMPLER(sampler_CameraDepthTexture);
            TEXTURE2D(_BlueNoiseTex);
            SAMPLER(sampler_BlueNoiseTex);
            #include "CloudHelp.hlsl"
            SAMPLER(sampler_LinearClamp);
            Texture2D _atmosphericScatteringLut;
            Texture2D _transmittanceLut;


            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 viewDir: TEXCOORD1;
            };

            v2f vert (appdata v)
            {
                v2f o;
                VertexPositionInputs vertexPos = GetVertexPositionInputs(v.vertex.xyz);
                o.vertex = vertexPos.positionCS;
                o.uv = v.uv;
                
                //用uv计算NDC空间，从NDC空间变换到相机空间
                float3 viewDir = mul(unity_CameraInvProjection, float4(v.uv * 2.0 - 1.0, 0, -1)).xyz;
                //相机空间到世界空间
                o.viewDir = mul(unity_CameraToWorld, float4(viewDir, 0)).xyz;

                return o;
            }

            half4 frag (v2f i) : SV_Target
            {
                half4 backColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);

                float depth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, i.uv).x;
                float dstToObj = LinearEyeDepth(depth, _ZBufferParams);

                //获取灯光信息
                Light mainLight = GetMainLight();

                float3 viewDir = normalize(i.viewDir);
                float3 lightDir = normalize(mainLight.direction);
                float3 cameraPos = GetCameraPositionWS();

                 //地球半径
                float earthRadius = _PlanetRadius;
                //地球中心坐标, 高度0为地表,
                float3 sphereCenter = float3(0, -earthRadius, 0);
                
                //dstToCloud是到云层的最近距离，dstInCloud是穿过云层的距离
                float2 dstCloud = RayCloudLayerDst(sphereCenter, earthRadius, _CloudAreaStart, _CloudAreaStart + _CloudAreaThickness, cameraPos, viewDir);
                float dstToCloud = dstCloud.x;
                float dstInCloud = dstCloud.y;

                //不在包围盒内、被物体遮挡、超过最远出发点,直接显示背景
                if (dstInCloud <= 0 || dstToObj <= dstToCloud || dstToCloud > _StartMaxDistance)
                {
                    return half4(0, 0, 0, 1);
                }

                //进行光线步进
                //设置采样信息
                SamplingInfo sampleInfo = GetSampleInfo(earthRadius);
                
                //从大气散射中获取光照信息
                AtmosphereParameter param = GetAtmosphereParameter();
                float3 sunColor = param.SunLightColor * param.SunLightIntensity * _SunLightScale;
                float3 skyBackgroundColor = _atmosphericScatteringLut.SampleLevel(sampler_LinearClamp, ViewDirToUV(viewDir), 0).rgb * _AmbientLightScale;

                //向前/向后散射
                float VoL = dot(viewDir, lightDir);
                float sunPhase = DualLobPhase(_CloudPhaseForward, _CloudPhaseBackward, _CloudPhaseMixFactor, -VoL);
                ParticipatingMediaPhase participatingMediaPhase = GetParticipatingMediaPhase(sunPhase, _CloudPhaseMixFactor);

                //穿出云覆盖范围的位置(结束位置)
                float endPos = dstToCloud + dstInCloud;
                //使用蓝噪声在对开始步进位置进行随机，配合TAA减轻因步进距离太大造成的层次感
                float2 blueNoiseUV = i.uv * _BlueNoiseTexUV  /* + float2(0.754877669, 0.569840296) * _CosTime.w / 100*/;
                float blueNoise = SAMPLE_TEXTURE2D(_BlueNoiseTex, sampler_BlueNoiseTex, blueNoiseUV).r;
                //当前步进长度
                float currentMarchLength = dstToCloud + _ShapeMarchLength * blueNoise * _BlueNoiseScale;
                //当前步进位置
                float3 currentPos = cameraPos + currentMarchLength * viewDir;

                //透射率，本质是通过参与介质后光强的衰减程度
                float transmittance = 1.0;
                //最终散射到相机处的光强
                float3 scattering = float3(0.0, 0.0, 0.0);

                //平均采样点高度，用于云的雾效果，即远处的云应该更不明显
                float3 rayHitPos = float3(0, 0, 0);
                float rayHitPosWeight = 0.0;

                //一开始我们会以比较大的步长进行步进(2倍步长)进行密度采样检测，当检测到云时，退回来进行正常云的采样、光照计算
                //当累计采样到一定次数0密度时，在切换成大步进，从而加速退出
                //云测试密度
                float densityTest = 0;
                //上一次采样密度
                float densityPrevious = 0;
                //0密度采样次数
                int densitySampleCount_zero = 0;

                //开始步进, 当超过步进次数、被物体遮挡、穿出云覆盖氛围时，结束步进
                [loop]
                for (int marchNumber = 0; marchNumber < _ShapeMarchMax; marchNumber++)
                {
                    if (densityTest == 0)
                    {
                        //向观察方向步进2倍的长度
                        currentMarchLength += _ShapeMarchLength * 2.0;
                        currentPos = cameraPos + currentMarchLength * viewDir;

                        //如果步进到被物体遮挡,或穿出云覆盖范围时,跳出循环
                        if (dstToObj <= currentMarchLength || endPos <= currentMarchLength)
                            break;

                        //进行密度采样，测试是否继续大步前进
                        densityTest = SampleCloudDensity(currentPos, sampleInfo);

                        //如果检测到云，往后退一步(因为我们可能错过了开始位置)
                        if (densityTest > 0)
                        {
                            currentMarchLength -= _ShapeMarchLength;
                        }
                    }
                    else
                    {
                        //采样该区域的密度
                        currentPos = cameraPos + currentMarchLength * viewDir;

                        float density = SampleCloudDensity(currentPos, sampleInfo);

                        rayHitPos += currentPos * transmittance;
                        rayHitPosWeight += transmittance;

                        //如果当前采样密度和上次采样密度都是0，那么进行累计，当到达指定数值时，切换到大步进
                        if (density == 0 && densityPrevious == 0)
                        {
                            densitySampleCount_zero++;
                            //累计检测到指定数值，切换到大步进
                            if (densitySampleCount_zero >= 8)
                            {
                                densityTest = 0;
                                densitySampleCount_zero = 0;
                                continue;
                            }
                        }

                        //密度大于0时计算transmittance和scattering
                        float opticalDepth = density * _ShapeMarchLength;
                        float stepTransmittance = exp(-opticalDepth);

                        //从大气层顶部到视线上点p的外散射损失
                        float3 atmosphereTransmittance = TransmittanceToAtmosphere(param, currentPos, lightDir, _transmittanceLut, sampler_LinearClamp);
                        
                        //除了大气的外散射，还需要考虑光线穿过云层的外散射
                        ParticipatingMediaTransmittance participatingMediaTransmittance = CloudTransmittance(currentPos, lightDir, sampleInfo);

                        //大气环境光和一个向上的地面Trace组成全部环境光
                        float3 ambientLight = skyBackgroundColor + GetGroundContribution(
                            currentPos,
                            lightDir,
                            sunColor,
                            atmosphereTransmittance,
                            param.GroundColor,
                            sampleInfo
                        ) * _GroundLightScale;

                        //Unreal engine 5's implement powder formula.
                        float powderEffectTerm = pow(saturate(opticalDepth * _CloudPowderScale), _CloudPowderPow);

                        //多重散射的非物理近似，本质是把各个部分按比例衰减后重新计算一次
                        float3 scatteringCoefficients[kMsCount];
                        float extinctionCoefficients[kMsCount];

                        float sigmaS = density;
                        float sigmaE = sigmaS + 1e-4f;

                        scatteringCoefficients[0] = sigmaS * powderEffectTerm * _CloudAlbedo.rgb;
                        extinctionCoefficients[0] = sigmaE;

                        float MsExtinctionFactor = _CloudMultiScatterExtinction;
                        float MsScatterFactor = _CloudMultiScatterScatter;
                        int ms;
                        [unroll(kMsCount)]
                        for (ms = 1; ms < kMsCount; ms++)
                        {
                            extinctionCoefficients[ms] = extinctionCoefficients[ms - 1] * MsExtinctionFactor;
                            scatteringCoefficients[ms] = scatteringCoefficients[ms - 1] * MsScatterFactor;

                            MsExtinctionFactor *= MsExtinctionFactor;
                            MsScatterFactor *= MsScatterFactor;
                        }
                        [unroll(kMsCount)]
                        for (ms = kMsCount - 1; ms >= 0; ms--)
                        {                            
                            float3 stepScattering = sunColor * participatingMediaPhase.phase[ms] * participatingMediaTransmittance.transmittanceToLight[ms];
                            stepScattering += ms == 0 ? ambientLight : float3(0, 0, 0);
                        
                            float3 sactterLitStep = stepScattering * scatteringCoefficients[ms];
                            sactterLitStep = atmosphereTransmittance * transmittance * (sactterLitStep - sactterLitStep * stepTransmittance) / max(1e-4f, extinctionCoefficients[ms]);
                            scattering += sactterLitStep;
                        }

                        transmittance *= stepTransmittance;
                        if (transmittance <= 0.001)
                        {
                            break;
                        }
                        //向前步进
                        currentMarchLength += _ShapeMarchLength;

                        //如果步进到被物体遮挡,或穿出云覆盖范围时,跳出循环
                        if (dstToObj <= currentMarchLength || endPos <= currentMarchLength)
                            break;
                        densityPrevious = density;
                    }
                }

                //混合Fade effect
                rayHitPos /= rayHitPosWeight;
                rayHitPos -= cameraPos;
                float rayHitHeight = length(rayHitPos);
                //浮点数误差，可能导致fading大于1
                float fading = saturate(exp(-rayHitHeight * _CloudFogFade * 10e-8));
                //近处fading接近1，从而cloudTransmittanceFaded接近transmittance
                //远处fading接近0，从而cloudTransmittanceFaded接近1
                float cloudTransmittanceFaded = lerp(1.0, transmittance, fading);

                //近处scattering不变，远处scattering减弱，防止远处混合背景后过亮
                return half4(scattering * (1 - cloudTransmittanceFaded), cloudTransmittanceFaded);
            }
            ENDHLSL
        }
        Pass
        {
            Blend One SrcAlpha

            HLSLPROGRAM

            #pragma vertex vert_blend
            #pragma fragment frag_blend

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            struct appdata
            {
                float4 vertex: POSITION;
                float2 uv: TEXCOORD0;
            };
            
            struct v2f
            {
                float4 vertex: SV_POSITION;
                float2 uv: TEXCOORD0;
            };

            v2f vert_blend(appdata v)
            {
                v2f o;
                
                VertexPositionInputs vertexPos = GetVertexPositionInputs(v.vertex.xyz);
                o.vertex = vertexPos.positionCS;
                o.uv = v.uv;
                return o;
            }

            half4 frag_blend(v2f i): SV_Target
            {
                return SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
            }

            ENDHLSL
        }
    }
}
