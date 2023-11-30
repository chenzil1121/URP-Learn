Shader "CZL/AerialPerspective"
{
    Properties
    {
        _MainTex("_MainTex", 2D) = "white" {}
    }
    SubShader
    {
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "AtmosphericHelp.hlsl"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.uv = v.uv;
                return o;
            }

            SAMPLER(sampler_PointClamp);
            SAMPLER(sampler_LinearClamp);
            Texture2D _MainTex;
            Texture2D _aerialPerspectiveLut;

            float _AerialPerspectiveDistance;
            float4 _AerialPerspectiveVoxelSize;

            float4 GetFragmentWorldPos(float2 screenPos)
            {
                float sceneRawDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, screenPos);
                float4 ndc = float4(screenPos.x * 2 - 1, screenPos.y * 2 - 1, sceneRawDepth, 1);
            #if UNITY_UV_STARTS_AT_TOP
                ndc.y *= -1;
            #endif
                float4 worldPos = mul(UNITY_MATRIX_I_VP, ndc);
                worldPos /= worldPos.w;

                return worldPos;
            }

            float4 frag(v2f i) : SV_Target
            {
                float2 uv = i.uv;
                float3 sceneColor = _MainTex.SampleLevel(sampler_LinearClamp, uv, 0).rgb;

                // ��պл��Ʋ����ܿ���͸��Ӱ��
                float sceneRawDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, uv);
            #if UNITY_REVERSED_Z
                if (sceneRawDepth == 0.0f) return float4(sceneColor, 1.0);
            #else
                if (sceneRawDepth == 1.0f) return float4(sceneColor, 1.0);
            #endif

                // �����������
                float3 worldPos = GetFragmentWorldPos(i.uv).xyz;
                float3 eyePos = _WorldSpaceCameraPos.xyz;
                float dis = length(worldPos - eyePos);
                float3 viewDir = normalize(worldPos - eyePos);

                // ���� slice ����
                float dis01 = saturate(dis / _AerialPerspectiveDistance);
                float dis0Z = dis01 * (_AerialPerspectiveVoxelSize.z - 1);  // [0 ~ SizeZ-1]
                float slice = floor(dis0Z);
                float nextSlice = min(slice + 1, _AerialPerspectiveVoxelSize.z - 1);
                float lerpFactor = dis0Z - floor(dis0Z);

                // ���� AerialPerspectiveVoxel
                uv.x /= _AerialPerspectiveVoxelSize.x;
                float2 uv1 = float2(uv.x + slice / _AerialPerspectiveVoxelSize.z, uv.y);
                float2 uv2 = float2(uv.x + nextSlice / _AerialPerspectiveVoxelSize.z, uv.y);

                float4 data1 = _aerialPerspectiveLut.SampleLevel(sampler_LinearClamp, uv1, 0);
                float4 data2 = _aerialPerspectiveLut.SampleLevel(sampler_LinearClamp, uv2, 0);
                float4 data = lerp(data1, data2, lerpFactor);

                float3 inScattering = data.xyz;
                float transmittance = data.w;
                
                return float4(sceneColor * transmittance + inScattering, 1.0);
            }

            ENDHLSL
        }
    }
}
