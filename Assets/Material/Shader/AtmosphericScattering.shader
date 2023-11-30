Shader "CZL/AtmosphericScattering"
{
    Properties
    {
        
    }
    SubShader
    {
        Tags { "Queue" = "Background" "RenderType" = "Background" "RenderPipeline" = "UniversalPipeline" "PreviewType" = "Skybox" }
        ZWrite Off

        Pass
        {
            HLSLPROGRAM

            #pragma target 5.0
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "AtmosphericHelp.hlsl"
            struct appdata
            {
                float3 vertex: POSITION;
            };

            struct v2f
            {
                float4 positionCS: SV_POSITION;
                float3 positionOS: TEXCOORD0;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.positionCS = TransformObjectToHClip(v.vertex);
                o.positionOS = v.vertex;
                return o;
            }

            float3 RenderSun(AtmosphereParameter param, float3 eyePos, float3 viewDir, float3 lightDir)
            {
                float3 planetCenter = float3(0, -param.PlanetRadius, 0);
                //�ֱ���ؿ��Լ�����������
                float2 disToAtmosphere = RaySphereIntersection(eyePos, viewDir, planetCenter, param.PlanetRadius + param.AtmosphereHeight);
                float2 disToPlanet = RaySphereIntersection(eyePos, viewDir, planetCenter, param.PlanetRadius);

                //�������ʱ���Լ�������ղ�������ʱ���Ǻڵ�
                if (disToAtmosphere.y < 0 || (disToAtmosphere.x < 0 && disToPlanet.x >= 0))
                    return half4(0, 0, 0, 1);
                else
                    return MiePhaseHG(dot(viewDir, lightDir), 0.999) * param.SunLightIntensity * param.SunDiskSize;
            }

            SAMPLER(sampler_LinearClamp);
            Texture2D _atmosphericScatteringLut;

            half4 frag(v2f i): SV_Target
            {
                AtmosphereParameter param = GetAtmosphereParameter();

                //��պе�����ʼ���������ΪԲ�ģ������ģ�͵ľֲ��������view����
                float3 rayDir = normalize(TransformObjectToWorld(i.positionOS));
                float3 lightDir = _MainLightPosition.xyz;

                float3 color = float3(0, 0, 0);

                color += _atmosphericScatteringLut.SampleLevel(sampler_LinearClamp, ViewDirToUV(rayDir), 0).rgb;

                color += RenderSun(param, _WorldSpaceCameraPos.xyz, rayDir, lightDir);

                return float4(color, 1);
            }

            ENDHLSL
        }
    }
}
