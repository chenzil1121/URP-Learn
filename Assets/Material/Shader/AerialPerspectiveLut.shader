Shader "CZL/AerialPerspectiveLut"
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

            float _AerialPerspectiveDistance;
            float4 _AerialPerspectiveVoxelSize;

            SAMPLER(sampler_LinearClamp);
            Texture2D _transmittanceLut;
            Texture2D _multiScatteringLut;

            float4 frag(v2f i) : SV_Target
            {
                AtmosphereParameter param = GetAtmosphereParameter();

                float4 color = float4(0, 0, 0, 1);
                float3 uv = float3(i.uv, 0);
                uv.x *= _AerialPerspectiveVoxelSize.x * _AerialPerspectiveVoxelSize.z;  // X * Z
                //�ҵ��ǵڼ���slice��Ȼ���һ����0-1
                uv.z = int(uv.x / _AerialPerspectiveVoxelSize.x) / _AerialPerspectiveVoxelSize.z;
                uv.x = fmod(uv.x, _AerialPerspectiveVoxelSize.z) / _AerialPerspectiveVoxelSize.x;
                //�ƶ���frustum voxel����
                uv.xyz += 0.5 / _AerialPerspectiveVoxelSize.xyz;

                float aspect = _ScreenParams.x / _ScreenParams.y;
                float3 viewDir = normalize(mul(unity_CameraToWorld, float4(
                    (uv.x * 2.0 - 1.0) * 1.0,
                    (uv.y * 2.0 - 1.0) / aspect,
                    1.0, 0.0
                    )).xyz);

                float3 lightDir = _MainLightPosition.xyz;
                float3 planetCenter = float3(0, -param.PlanetRadius, 0);
                float3 eyePos = _WorldSpaceCameraPos.xyz;
                float maxDis = uv.z * _AerialPerspectiveDistance;

                //inScattering
                //���ﲻ����AtmosphericScatteringLut��ԭ���ǣ�inScattering��Ч��Ӧ����ֹ��������棬������һֱ�������㶥��
                //�ֱ���ؿ��Լ�����������
                float2 disToAtmosphere = RaySphereIntersection(eyePos, viewDir, planetCenter, param.PlanetRadius + param.AtmosphereHeight);
                float2 disToPlanet = RaySphereIntersection(eyePos, viewDir, planetCenter, param.PlanetRadius);

                float dis = disToAtmosphere.y;
                if (disToPlanet.x > 0)
                    dis = min(disToAtmosphere.y, disToPlanet.x);
                //��ͬslice�Ļ���·������Ӧ�ò�ͬ
                dis = min(dis, maxDis);

                float step = dis / float(N_SAMPLE);
                float3 inScatteringColor = float3(0, 0, 0);

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
                    inScatteringColor += inScattering;

                    //����ɢ��
                    float3 multiScattering = GetMultiScattering(param, p, lightDir, _multiScatteringLut, sampler_LinearClamp);
                    inScatteringColor += multiScattering * t2 * step * sunLuminance;

                    p += viewDir * step;
                }
                color.rgb = inScatteringColor;

                //transmittance
                float3 voxelPos = eyePos + viewDir * maxDis;
                float3 t1 = TransmittanceToAtmosphere(param, eyePos, viewDir, _transmittanceLut, sampler_LinearClamp);
                float3 t2 = TransmittanceToAtmosphere(param, voxelPos, viewDir, _transmittanceLut, sampler_LinearClamp);
                float3 t = t1 / t2;
                //��ΪinScattering��transmittance����float3��Ϊ��ֻ��һ���������԰�transmittance��ѹ��
                color.a = dot(t, float3(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0));

                return color;
            }

            ENDHLSL
        }
    }
}
