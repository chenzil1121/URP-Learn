Shader "CZL/TransmittanceLut"
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

            float4 frag(v2f i) : SV_Target
            {
                AtmosphereParameter param = GetAtmosphereParameter();

                float4 color = float4(0, 0, 0, 1);
                float2 uv = i.uv;

                float bottomRadius = param.PlanetRadius;
                float topRadius = param.PlanetRadius + param.AtmosphereHeight;
                float3 planetCenter = float3(0, -param.PlanetRadius, 0);

                // 计算当前 uv 对应的 cos_theta, height
                float cos_theta = 0.0;
                float r = 0.0;
                UvToTransmittanceLutParams(bottomRadius, topRadius, uv, cos_theta, r);

                float sin_theta = sqrt(1.0 - cos_theta * cos_theta);
                float3 viewDir = float3(sin_theta, cos_theta, 0);
                float3 eyePos = float3(0, r - param.PlanetRadius, 0);

                // 光线和大气层求交
                float dis = RaySphereIntersection(eyePos, viewDir, planetCenter, param.PlanetRadius + param.AtmosphereHeight).y;
                float3 hitPoint = eyePos + viewDir * dis;
                //从大气层顶部到预计算点处的外散射损失
                color.rgb = Transmittance(param, eyePos, hitPoint);

                return color;
            }

            ENDHLSL
        }
    }
}
