Shader "CZL/DDGIProbeVis"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        Pass
        {
            Blend Off
            ZWrite Off
            ZTest LEqual

            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #define DEBUG_DISPLAY
            #include "Packages/com.unity.render-pipelines.universal/Shaders/UnlitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/UnlitForwardPass.hlsl"


            sampler2D _MainTex;
            float4 _MainTex_ST;

            Varyings vert (Attributes input)
            {
                Varyings output = (Varyings)0;

                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);

                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);

                output.positionCS = vertexInput.positionCS;
                output.uv = input.uv;

                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                half3 viewDirWS = GetWorldSpaceViewDir(vertexInput.positionWS);

                output.positionWS = vertexInput.positionWS;
                output.normalWS = normalInput.normalWS;
                output.viewDirWS = viewDirWS;

                return output;
            }

            half4 frag(Varyings i) : SV_Target
            {
                // sample the texture
                float4 col = float4(1,1,1,1);
                //float4 col = float4(i.uv.x,i.uv.y,0,1);
                //float4 col = float4(i.normalWS, 1);
                return col;
            }
            ENDHLSL
        }
    }
}
