Shader "CZL/DDGIIndirectLight"
{
    Properties
    {
        [HideInInspector] _MainTex("Texture", 2D) = "white" {}
        
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
        #include "DDGICommon.hlsl"
        //暂时不考虑Accurate G-Buffer normals
        //#include "Packages/com.unity.render-pipelines.universal/Shaders/Utils/UnityGBuffer.hlsl"
        ENDHLSL

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            TEXTURE2D(_GBuffer0);
            TEXTURE2D(_GBuffer2);

            SAMPLER(sampler_LinearClamp);
            Texture2DArray _ProbeDistance;
            Texture2DArray _ProbeIrradiance;

            CBUFFER_START(UnityPerMaterial)
            int4 _ProbeCount;
            float4 _ProbeSpacing;
            float4 _Origin;
            float _ProbeIrradianceEncodingGamma;
            int _ProbeNumDistanceInteriorTexels;
            int _ProbeNumIrradianceInteriorTexels;
            float _ProbeNormalBias;
            float _ProbeViewBias;
            CBUFFER_END


            struct appdata
            {
                float4 vertex : POSITION;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
            };

            v2f vert (appdata v)
            {
                v2f o;
                VertexPositionInputs vertexPos = GetVertexPositionInputs(v.vertex.xyz);
                o.vertex = vertexPos.positionCS;
                
                return o;
            }

            half4 frag (v2f i) : SV_Target
            {
                float2 uv = i.vertex.xy / _ScaledScreenParams.xy;
#if UNITY_REVERSED_Z
                real depth = SampleSceneDepth(uv);
#else
                // Adjust Z to match NDC for OpenGL ([-1, 1])
                real depth = lerp(UNITY_NEAR_CLIP_VALUE, 1, SampleSceneDepth(uv));
#endif
                float3 worldPos = ComputeWorldSpacePosition(uv, depth, UNITY_MATRIX_I_VP);
                float3 cameraPos = GetCameraPositionWS();
                float3 view = normalize(worldPos - cameraPos);
                half4 directColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv);

                float3 albedo = _GBuffer0.Load(int3(i.vertex.xy, 0)).rgb;
                float3 normal = normalize(_GBuffer2.Load(int3(i.vertex.xy, 0)).xyz);
                //normal = normalize(UnpackNormal(normal));

                float3 surfaceBias = DDGIGetSurfaceBias(normal, view, _ProbeNormalBias, _ProbeViewBias);
                float3 irradiance = float3(0, 0, 0);
                float blendWeight = DDGIGetVolumeBlendWeight(worldPos, _Origin.xyz, _ProbeCount.xyz, _ProbeSpacing.xyz);
                if (blendWeight > 0)
                {
                    irradiance = DDGIGetVolumeIrradiance(
                        worldPos,
                        surfaceBias,
                        normal,
                        _Origin.xyz,
                        _ProbeCount.xyz,
                        _ProbeSpacing.xyz,
                        _ProbeNumDistanceInteriorTexels,
                        _ProbeNumIrradianceInteriorTexels,
                        _ProbeIrradianceEncodingGamma,
                        _ProbeDistance,
                        _ProbeIrradiance,
                        sampler_LinearClamp
                    );
                }

                float3 indirectColor = (albedo / PI) * irradiance;
                
                return float4(directColor.rgb + indirectColor, directColor.a);
            }
            ENDHLSL
        }
    }
}
