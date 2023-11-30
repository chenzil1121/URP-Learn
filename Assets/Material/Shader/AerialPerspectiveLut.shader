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
                //找到是第几个slice，然后归一化到0-1
                uv.z = int(uv.x / _AerialPerspectiveVoxelSize.x) / _AerialPerspectiveVoxelSize.z;
                uv.x = fmod(uv.x, _AerialPerspectiveVoxelSize.z) / _AerialPerspectiveVoxelSize.x;
                //移动至frustum voxel中心
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
                //这里不能用AtmosphericScatteringLut的原因是，inScattering的效果应该终止于物体表面，而不是一直到大气层顶部
                //分别与地壳以及大气顶层求交
                float2 disToAtmosphere = RaySphereIntersection(eyePos, viewDir, planetCenter, param.PlanetRadius + param.AtmosphereHeight);
                float2 disToPlanet = RaySphereIntersection(eyePos, viewDir, planetCenter, param.PlanetRadius);

                float dis = disToAtmosphere.y;
                if (disToPlanet.x > 0)
                    dis = min(disToAtmosphere.y, disToPlanet.x);
                //不同slice的积分路径长度应该不同
                dis = min(dis, maxDis);

                float step = dis / float(N_SAMPLE);
                float3 inScatteringColor = float3(0, 0, 0);

                float3 p = eyePos + (viewDir * step) * 0.5;
                float3 sunLuminance = param.SunLightColor * param.SunLightIntensity;
                float3 opticalDepth = float3(0, 0, 0);

                for (int i = 0; i < N_SAMPLE; i++)
                {
                    //积累光学深度
                    float h = length(p - planetCenter) - param.PlanetRadius;
                    float3 extinction = RayleighCoefficient(param, h) + MieCoefficient(param, h) +  // scattering
                        OzoneAbsorption(param, h) + MieAbsorption(param, h);      // absorption
                    opticalDepth += extinction * step;

                    //从大气层顶部到视线上点p的外散射损失
                    float3 t1 = TransmittanceToAtmosphere(param, p, lightDir, _transmittanceLut, sampler_LinearClamp);
                    //在点p处散射到视线方向的比例
                    float3 s = Scattering(param, p, lightDir, viewDir);
                    //从点p到相机的视线方向上的外散射损失
                    float3 t2 = exp(-opticalDepth);

                    //单次散射
                    float3 inScattering = t1 * s * t2 * step * sunLuminance;
                    inScatteringColor += inScattering;

                    //多重散射
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
                //因为inScattering和transmittance都是float3，为了只用一张纹理，可以把transmittance简化压缩
                color.a = dot(t, float3(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0));

                return color;
            }

            ENDHLSL
        }
    }
}
