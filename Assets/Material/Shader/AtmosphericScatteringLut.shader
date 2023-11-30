Shader "CZL/AtmosphericScatteringLut"
{
    Properties
    {
        
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

            SAMPLER(sampler_LinearClamp);
            Texture2D _transmittanceLut;
            Texture2D _multiScatteringLut;

            float4 frag(v2f i) : SV_Target
            {
                AtmosphereParameter param = GetAtmosphereParameter();

                float3 eyePos = _WorldSpaceCameraPos.xyz;
                float3 viewDir = UVToViewDir(i.uv);
                float3 lightDir = _MainLightPosition.xyz;
                float3 planetCenter = float3(0, -param.PlanetRadius, 0);

                //�ֱ���ؿ��Լ�����������
                float2 disToAtmosphere = RaySphereIntersection(eyePos, viewDir, planetCenter, param.PlanetRadius + param.AtmosphereHeight);
                float2 disToPlanet = RaySphereIntersection(eyePos, viewDir, planetCenter, param.PlanetRadius);

                //�������ʱ���Լ�������ղ�������ʱ���Ǻڵ�
                if (disToAtmosphere.y < 0 || (disToAtmosphere.x < 0 && disToPlanet.x >= 0))
                    return half4(param.GroundColor, 1);

                float rayLength = disToAtmosphere.y;

                float step = rayLength / float(N_SAMPLE);
                float3 color = float3(0, 0, 0);

                float3 p = eyePos + (viewDir * step) * 0.5;
                float3 sunLuminance = param.SunLightColor * param.SunLightIntensity;
                float3 opticalDepth = float3(0, 0, 0);

                for (int i = 0; i < N_SAMPLE; i++)
                {
                    //���۹�ѧ���
                    float h = length(p - planetCenter) - param.PlanetRadius;
                    float3 extinction = RayleighCoefficient(param, h) + MieCoefficient(param, h) +  // scattering
                        OzoneAbsorption(param, h) + MieAbsorption(param, h);      // absorption
                    opticalDepth += extinction * step;

                    //�Ӵ����㶥���������ϵ�p����ɢ����ʧ
                    float3 t1 = TransmittanceToAtmosphere(param, p, lightDir, _transmittanceLut, sampler_LinearClamp);
                    //�ڵ�p��ɢ�䵽���߷���ı���
                    float3 s = Scattering(param, p, lightDir, viewDir);
                    //�ӵ�p����������߷����ϵ���ɢ����ʧ
                    float3 t2 = exp(-opticalDepth);

                    //����ɢ��
                    float3 inScattering = t1 * s * t2 * step * sunLuminance;
                    color += inScattering;

                    //����ɢ��
                    float3 multiScattering = GetMultiScattering(param, p, lightDir, _multiScatteringLut, sampler_LinearClamp);
                    color += multiScattering * t2 * step * sunLuminance;

                    p += viewDir * step;
                }

                return float4(color, 1);
            }

            ENDHLSL
        }
    }
}
