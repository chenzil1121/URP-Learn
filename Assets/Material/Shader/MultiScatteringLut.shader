Shader "CZL/MultiScatteringLut"
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

            float4 frag(v2f i) : SV_Target
            {
                AtmosphereParameter param = GetAtmosphereParameter();

                float4 color = float4(0, 0, 0, 1);
                float2 uv = i.uv;

                float mu_s = uv.x * 2.0 - 1.0;
                float cos_theta = mu_s;
                float sin_theta = sqrt(1.0 - cos_theta * cos_theta);
                float r = uv.y * param.AtmosphereHeight;

                float3 lightDir = float3(sin_theta, cos_theta, 0);
                float3 p = float3(0, r, 0);
                float3 planetCenter = float3(0, -param.PlanetRadius, 0);

                float3 RandomSphereSamples[64] = {
                    float3(-0.7838,-0.620933,0.00996137),
                    float3(0.106751,0.965982,0.235549),
                    float3(-0.215177,-0.687115,-0.693954),
                    float3(0.318002,0.0640084,-0.945927),
                    float3(0.357396,0.555673,0.750664),
                    float3(0.866397,-0.19756,0.458613),
                    float3(0.130216,0.232736,-0.963783),
                    float3(-0.00174431,0.376657,0.926351),
                    float3(0.663478,0.704806,-0.251089),
                    float3(0.0327851,0.110534,-0.993331),
                    float3(0.0561973,0.0234288,0.998145),
                    float3(0.0905264,-0.169771,0.981317),
                    float3(0.26694,0.95222,-0.148393),
                    float3(-0.812874,-0.559051,-0.163393),
                    float3(-0.323378,-0.25855,-0.910263),
                    float3(-0.1333,0.591356,-0.795317),
                    float3(0.480876,0.408711,0.775702),
                    float3(-0.332263,-0.533895,-0.777533),
                    float3(-0.0392473,-0.704457,-0.708661),
                    float3(0.427015,0.239811,0.871865),
                    float3(-0.416624,-0.563856,0.713085),
                    float3(0.12793,0.334479,-0.933679),
                    float3(-0.0343373,-0.160593,-0.986423),
                    float3(0.580614,0.0692947,0.811225),
                    float3(-0.459187,0.43944,0.772036),
                    float3(0.215474,-0.539436,-0.81399),
                    float3(-0.378969,-0.31988,-0.868366),
                    float3(-0.279978,-0.0109692,0.959944),
                    float3(0.692547,0.690058,0.210234),
                    float3(0.53227,-0.123044,-0.837585),
                    float3(-0.772313,-0.283334,-0.568555),
                    float3(-0.0311218,0.995988,-0.0838977),
                    float3(-0.366931,-0.276531,-0.888196),
                    float3(0.488778,0.367878,-0.791051),
                    float3(-0.885561,-0.453445,0.100842),
                    float3(0.71656,0.443635,0.538265),
                    float3(0.645383,-0.152576,-0.748466),
                    float3(-0.171259,0.91907,0.354939),
                    float3(-0.0031122,0.9457,0.325026),
                    float3(0.731503,0.623089,-0.276881),
                    float3(-0.91466,0.186904,0.358419),
                    float3(0.15595,0.828193,-0.538309),
                    float3(0.175396,0.584732,0.792038),
                    float3(-0.0838381,-0.943461,0.320707),
                    float3(0.305876,0.727604,0.614029),
                    float3(0.754642,-0.197903,-0.62558),
                    float3(0.217255,-0.0177771,-0.975953),
                    float3(0.140412,-0.844826,0.516287),
                    float3(-0.549042,0.574859,-0.606705),
                    float3(0.570057,0.17459,0.802841),
                    float3(-0.0330304,0.775077,0.631003),
                    float3(-0.938091,0.138937,0.317304),
                    float3(0.483197,-0.726405,-0.48873),
                    float3(0.485263,0.52926,0.695991),
                    float3(0.224189,0.742282,-0.631472),
                    float3(-0.322429,0.662214,-0.676396),
                    float3(0.625577,-0.12711,0.769738),
                    float3(-0.714032,-0.584461,-0.385439),
                    float3(-0.0652053,-0.892579,-0.446151),
                    float3(0.408421,-0.912487,0.0236566),
                    float3(0.0900381,0.319983,0.943135),
                    float3(-0.708553,0.483646,0.513847),
                    float3(0.803855,-0.0902273,0.587942),
                    float3(-0.0555802,-0.374602,-0.925519),
                };
                const float uniform_phase = 1.0 / (4.0 * PI);
                const float sphereSolidAngle = 4.0 * PI / float(N_SAMPLE);

                float3 G_2 = float3(0, 0, 0);
                float3 f_ms = float3(0, 0, 0);

                //采样了G_2和f_ms外围立体角积分变量的viewDir
                for (int i = 0; i < N_SAMPLE; i++)
                {
                    //分别与地壳以及大气顶层求交
                    float3 viewDir = RandomSphereSamples[i];
                    float2 disToAtmosphere = RaySphereIntersection(p, viewDir, planetCenter, param.PlanetRadius + param.AtmosphereHeight);
                    float2 disToPlanet = RaySphereIntersection(p, viewDir, planetCenter, param.PlanetRadius);

                    float dis = disToAtmosphere.y;
                    if (disToPlanet.x > 0)
                        dis = min(disToAtmosphere.y, disToPlanet.x);
                    
                    float ds = dis / float(N_SAMPLE);

                    float3 samplePoint = p + (viewDir * ds) * 0.5;
                    float3 opticalDepth = float3(0, 0, 0);

                    //每个方向上的RayMarching
                    for (int j = 0; j < N_SAMPLE; j++)
                    {
                        float h = length(samplePoint - planetCenter) - param.PlanetRadius;

                        float3 sigma_s = RayleighCoefficient(param, h) + MieCoefficient(param, h);  // scattering
                        float3 sigma_a = OzoneAbsorption(param, h) + MieAbsorption(param, h);       // absorption
                        float3 sigma_t = sigma_s + sigma_a;                                         // extinction
                        opticalDepth += sigma_t * ds;

                        float3 t1 = TransmittanceToAtmosphere(param, samplePoint, lightDir, _transmittanceLut, sampler_LinearClamp);
                        float3 s = Scattering(param, samplePoint, lightDir, viewDir);
                        float3 t2 = exp(-opticalDepth);

                        // 用 1.0 代替太阳光颜色, 该变量在后续的计算中乘上去
                        G_2 += t1 * s * t2 * uniform_phase * ds * 1.0;
                        f_ms += t2 * sigma_s * uniform_phase * ds;

                        samplePoint += viewDir * ds;
                    }                       
                }

                G_2 *= sphereSolidAngle;
                f_ms *= sphereSolidAngle;
                return float4(G_2 * (1.0 / (1.0 - f_ms)), 1.0);
            }

            ENDHLSL
        }
    }
}
