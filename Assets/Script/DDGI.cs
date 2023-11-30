using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class DDGI : ScriptableRendererFeature
{
    class DDGIProbeTracingPass : ScriptableRenderPass
    {
        public RayTracingAccelerationStructure accelerationStructure;
        public RayTracingShader probeRayTracingShader;
        public DDGIVolumeDesc volumeDesc;
        public AtmosphereSettings atmosphereSettings;

        private RenderTexture rayDataTex;
        public RenderTargetIdentifier rayDataTexIdentifier;

        public RenderTargetIdentifier probeIrradianceTexIdentifier;
        public RenderTargetIdentifier probeDistanceTexIdentifier;

        public void CreateRayDataTexture()
        {
            if (rayDataTex == null || !rayDataTex.IsCreated()) 
            {
                RenderTextureDescriptor rayDataTexDesc = new RenderTextureDescriptor
                {
                    enableRandomWrite = true,
                    autoGenerateMips = false,
                    bindMS = false,
                    colorFormat = RenderTextureFormat.ARGBFloat,
                    depthBufferBits = 0,
                    depthStencilFormat = GraphicsFormat.None,
                    graphicsFormat = GraphicsFormat.R32G32B32A32_SFloat,
                    useMipMap = false,
                    useDynamicScale = false,
                    dimension = TextureDimension.Tex2DArray,
                    sRGB = false,
                    mipCount = 1,
                    msaaSamples = 1,
                    //每个切片保存的是该平面上每一个探针发射的每一根光线的数据
                    width = volumeDesc.probeNumRays,
                    height = volumeDesc.probeCounts.x * volumeDesc.probeCounts.z,
                    //Probe坐标系是Y轴向上
                    volumeDepth = volumeDesc.probeCounts.y,
                };
                
                rayDataTex = new RenderTexture(rayDataTexDesc);
                rayDataTex.Create();
                rayDataTexIdentifier = new RenderTargetIdentifier(rayDataTex);
            }
        }

        public void ClearRayDataTexture()
        {
            if (rayDataTex != null)
                rayDataTex.Release();
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            CreateRayDataTexture();
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            Vector4 lightPos;
            Vector4 lightColor;
            //内部已经对lightDir反向处理了
            UniversalRenderPipeline.InitializeLightConstants_Common(
                renderingData.lightData.visibleLights, 
                renderingData.lightData.mainLightIndex, 
                out lightPos, 
                out lightColor, 
                out _, out _, out _);            

            volumeDesc.ComputeRandomRotation();

            CommandBuffer cmd = CommandBufferPool.Get(name: "DDGI Probe Tracing");

            cmd.BuildRayTracingAccelerationStructure(accelerationStructure);

            cmd.SetRayTracingShaderPass(probeRayTracingShader, "TracingAlbedoPass");
            cmd.SetRayTracingAccelerationStructure(probeRayTracingShader, "_RaytracingAccelerationStructure", accelerationStructure);
            
            int[] probeCount = new int[3];
            probeCount[0] = volumeDesc.probeCounts.x;
            probeCount[1] = volumeDesc.probeCounts.y;
            probeCount[2] = volumeDesc.probeCounts.z;
            cmd.SetRayTracingIntParams(probeRayTracingShader, "_ProbeCount", probeCount);
            float[] probeSpacing = new float[3];
            probeSpacing[0] = volumeDesc.probeSpacing.x;
            probeSpacing[1] = volumeDesc.probeSpacing.y;
            probeSpacing[2] = volumeDesc.probeSpacing.z;
            cmd.SetRayTracingFloatParams(probeRayTracingShader, "_ProbeSpacing", probeSpacing);
            float[] origin = new float[3];
            origin[0] = volumeDesc.origin.x;
            origin[1] = volumeDesc.origin.y;
            origin[2] = volumeDesc.origin.z;
            cmd.SetRayTracingFloatParams(probeRayTracingShader, "_Origin", origin);
            cmd.SetRayTracingIntParam(probeRayTracingShader, "_ProbeNumRays", volumeDesc.probeNumRays);
            cmd.SetRayTracingIntParam(probeRayTracingShader, "_ProbeNumDistanceInteriorTexels", volumeDesc.probeNumDistanceInteriorTexels);
            cmd.SetRayTracingIntParam(probeRayTracingShader, "_ProbeNumIrradianceInteriorTexels", volumeDesc.probeNumIrradianceInteriorTexels);
            cmd.SetRayTracingVectorParam(probeRayTracingShader, "_ProbeRayRotation", volumeDesc.probeRayRotation);
            cmd.SetRayTracingFloatParam(probeRayTracingShader, "_ProbeNormalBias", volumeDesc.probeNormalBias);
            cmd.SetRayTracingFloatParam(probeRayTracingShader, "_ProbeViewBias", volumeDesc.probeViewBias);
            cmd.SetRayTracingFloatParam(probeRayTracingShader, "_ProbeMaxRayDistance", volumeDesc.probeMaxRayDistance);
            cmd.SetRayTracingFloatParam(probeRayTracingShader, "_ProbeIrradianceEncodingGamma", volumeDesc.probeIrradianceEncodingGamma);
            cmd.SetRayTracingVectorParam(probeRayTracingShader, "_MainLightPosition", lightPos);
            cmd.SetRayTracingVectorParam(probeRayTracingShader, "_MainLightColor", lightColor);

            cmd.SetRayTracingTextureParam(probeRayTracingShader, "_RayData", rayDataTexIdentifier);
            cmd.SetRayTracingTextureParam(probeRayTracingShader, "_ProbeDistance", probeDistanceTexIdentifier);
            cmd.SetRayTracingTextureParam(probeRayTracingShader, "_ProbeIrradiance", probeIrradianceTexIdentifier);
            //cmd.SetRayTracingTextureParam(probeRayTracingShader, "_AtmosphericScatteringLut", atmosphereSettings.AtmosphericScatteringLut);
            //每个Probe每根光线Dispatch
            cmd.DispatchRays(probeRayTracingShader, "ProbeRayGenShader", (uint)volumeDesc.probeNumRays, (uint)(volumeDesc.probeCounts.x * volumeDesc.probeCounts.z), (uint)volumeDesc.probeCounts.y);

            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            
        }
    }

    class DDGIProbeUpdatePass : ScriptableRenderPass
    {
        public ComputeShader probeUpdateShader;
        public DDGIVolumeDesc volumeDesc;

        private RenderTexture probeIrradianceTex;
        public RenderTargetIdentifier probeIrradianceTexIdentifier;

        private RenderTexture probeDistanceTex;
        public RenderTargetIdentifier probeDistanceTexIdentifier;

        public RenderTargetIdentifier rayDataTexIdentifier;

        public void CreateTexture()
        {
            if (probeIrradianceTex == null || !probeIrradianceTex.IsCreated())
            {
                RenderTextureDescriptor TexDesc = new RenderTextureDescriptor
                {
                    enableRandomWrite = true,
                    autoGenerateMips = false,
                    bindMS = false,
                    colorFormat = RenderTextureFormat.ARGBFloat,
                    depthBufferBits = 0,
                    depthStencilFormat = GraphicsFormat.None,
                    graphicsFormat = GraphicsFormat.R32G32B32A32_SFloat,
                    useMipMap = false,
                    useDynamicScale = false,
                    dimension = TextureDimension.Tex2DArray,
                    sRGB = false,
                    mipCount = 1,
                    msaaSamples = 1,
                    //每个Probe映射到一块八面体纹素区域
                    width = volumeDesc.probeCounts.x * (volumeDesc.probeNumIrradianceInteriorTexels + 2),
                    height = volumeDesc.probeCounts.z * (volumeDesc.probeNumIrradianceInteriorTexels + 2),
                    //Probe坐标系是Y轴向上
                    volumeDepth = volumeDesc.probeCounts.y,
                };

                probeIrradianceTex = new RenderTexture(TexDesc);
                probeIrradianceTex.Create();
                probeIrradianceTexIdentifier = new RenderTargetIdentifier(probeIrradianceTex);
            }

            if (probeDistanceTex == null || !probeDistanceTex.IsCreated())
            {
                RenderTextureDescriptor TexDesc = new RenderTextureDescriptor
                {
                    enableRandomWrite = true,
                    autoGenerateMips = false,
                    bindMS = false,
                    colorFormat = RenderTextureFormat.ARGBFloat,
                    depthBufferBits = 0,
                    depthStencilFormat = GraphicsFormat.None,
                    graphicsFormat = GraphicsFormat.R32G32B32A32_SFloat,
                    useMipMap = false,
                    useDynamicScale = false,
                    dimension = TextureDimension.Tex2DArray,
                    sRGB = false,
                    mipCount = 1,
                    msaaSamples = 1,
                    //每个Probe映射到一块八面体纹素区域
                    width = volumeDesc.probeCounts.x * (volumeDesc.probeNumDistanceInteriorTexels + 2),
                    height = volumeDesc.probeCounts.z * (volumeDesc.probeNumDistanceInteriorTexels + 2),
                    //Probe坐标系是Y轴向上
                    volumeDepth = volumeDesc.probeCounts.y,
                };

                probeDistanceTex = new RenderTexture(TexDesc);
                probeDistanceTex.Create();
                probeDistanceTexIdentifier = new RenderTargetIdentifier(probeDistanceTex);
            }
        }

        public void ClearTexture()
        {
            if (probeIrradianceTex != null)
                probeIrradianceTex.Release();

            if (probeDistanceTex != null)
                probeDistanceTex.Release();
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            CreateTexture();
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get(name: "DDGI Probe Update");

            int[] probeCount = new int[4];
            probeCount[0] = volumeDesc.probeCounts.x;
            probeCount[1] = volumeDesc.probeCounts.y;
            probeCount[2] = volumeDesc.probeCounts.z;
            probeCount[3] = 1;
            cmd.SetComputeIntParams(probeUpdateShader, "_ProbeCount", probeCount);
            float[] probeSpacing = new float[4];
            probeSpacing[0] = volumeDesc.probeSpacing.x;
            probeSpacing[1] = volumeDesc.probeSpacing.y;
            probeSpacing[2] = volumeDesc.probeSpacing.z;
            probeSpacing[3] = 1;
            cmd.SetComputeFloatParams(probeUpdateShader, "_ProbeSpacing", probeSpacing);
            cmd.SetComputeIntParam(probeUpdateShader, "_ProbeNumRays", volumeDesc.probeNumRays);
            cmd.SetComputeVectorParam(probeUpdateShader, "_ProbeRayRotation", volumeDesc.probeRayRotation);
            cmd.SetComputeFloatParam(probeUpdateShader, "_Hysteresis", volumeDesc.probeHysteresis);
            cmd.SetComputeFloatParam(probeUpdateShader, "_IrradianceEncodingGamma", volumeDesc.probeIrradianceEncodingGamma);

            int irradianceKernelID = probeUpdateShader.FindKernel("ProbeIrradiance");
            cmd.SetComputeIntParam(probeUpdateShader, "_ProbeNumTexels", (volumeDesc.probeNumIrradianceInteriorTexels + 2));
            cmd.SetComputeTextureParam(probeUpdateShader, irradianceKernelID, "_Result", probeIrradianceTexIdentifier);
            cmd.SetComputeTextureParam(probeUpdateShader, irradianceKernelID, "_RayData", rayDataTexIdentifier);
            cmd.DispatchCompute(probeUpdateShader, irradianceKernelID, volumeDesc.probeCounts.x, volumeDesc.probeCounts.z, volumeDesc.probeCounts.y);

            int distanceKernelID = probeUpdateShader.FindKernel("ProbeDistance");
            cmd.SetComputeIntParam(probeUpdateShader, "_ProbeNumTexels", (volumeDesc.probeNumDistanceInteriorTexels + 2));
            cmd.SetComputeTextureParam(probeUpdateShader, distanceKernelID, "_Result", probeDistanceTexIdentifier);
            cmd.SetComputeTextureParam(probeUpdateShader, distanceKernelID, "_RayData", rayDataTexIdentifier);
            cmd.DispatchCompute(probeUpdateShader, distanceKernelID, volumeDesc.probeCounts.x, volumeDesc.probeCounts.z, volumeDesc.probeCounts.y);

            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            
        }
    }

    class DDGIIndirectLightPass : ScriptableRenderPass
    {
        private RenderTargetIdentifier cameraColorTex;
        private int width;
        private int height;

        public Material indirectLightMaterial;
        public DDGIVolumeDesc volumeDesc;
        public RenderTargetIdentifier probeIrradianceTexIdentifier;
        public RenderTargetIdentifier probeDistanceTexIdentifier;

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            width = renderingData.cameraData.cameraTargetDescriptor.width;
            height = renderingData.cameraData.cameraTargetDescriptor.height;
            cameraColorTex = renderingData.cameraData.renderer.cameraColorTarget;
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get(name: "DDGIIndirectLight");

            //创建临时渲染纹理
            RenderTextureDescriptor temDescriptor = new RenderTextureDescriptor(width, height, RenderTextureFormat.ARGB32);
            temDescriptor.depthBufferBits = 0;
            int temTextureID = Shader.PropertyToID("_DDGIIndirectTex");
            cmd.GetTemporaryRT(temTextureID, temDescriptor);

            cmd.SetGlobalTexture("_ProbeDistance", probeDistanceTexIdentifier);
            cmd.SetGlobalTexture("_ProbeIrradiance", probeIrradianceTexIdentifier);
            Vector4 probeCount = new Vector4(
                volumeDesc.probeCounts.x,
                volumeDesc.probeCounts.y,
                volumeDesc.probeCounts.z, 
                1);
            cmd.SetGlobalVector("_ProbeCount", probeCount);
            Vector4 probeSpacing = new Vector4(
                volumeDesc.probeSpacing.x,
                volumeDesc.probeSpacing.y,
                volumeDesc.probeSpacing.z,
                1);
            cmd.SetGlobalVector("_ProbeSpacing", probeSpacing);
            Vector4 origin = new Vector4(
                volumeDesc.origin.x,
                volumeDesc.origin.y,
                volumeDesc.origin.z,
                1);
            cmd.SetGlobalVector("_Origin", origin);
            cmd.SetGlobalFloat("_ProbeIrradianceEncodingGamma", volumeDesc.probeIrradianceEncodingGamma);
            cmd.SetGlobalFloat("_ProbeNormalBias", volumeDesc.probeNormalBias);
            cmd.SetGlobalFloat("_ProbeViewBias", volumeDesc.probeViewBias);
            cmd.SetGlobalInteger("_ProbeNumDistanceInteriorTexels", volumeDesc.probeNumDistanceInteriorTexels);
            cmd.SetGlobalInteger("_ProbeNumIrradianceInteriorTexels", volumeDesc.probeNumIrradianceInteriorTexels);

            cmd.Blit(cameraColorTex, temTextureID, indirectLightMaterial, 0);
            cmd.Blit(temTextureID, cameraColorTex);
            //执行
            context.ExecuteCommandBuffer(cmd);
            //释放资源
            cmd.ReleaseTemporaryRT(temTextureID);

            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        { 
        }

    }

    DDGIProbeTracingPass probeTracingPass;
    DDGIProbeUpdatePass probeUpdatePass;
    DDGIIndirectLightPass indirectLightPass;
    public RayTracingAccelerationStructure accelerationStructure;
    [SerializeField] RayTracingShader probeRayTracingShader;
    [SerializeField] ComputeShader probeUpdateShader;
    [SerializeField] Shader indirectLightShader;
    [SerializeField] DDGIVolumeDesc volumeDesc;
    [SerializeField] AtmosphereSettings atmosphereSettings;

    public override void Create()
    {
        probeTracingPass = new DDGIProbeTracingPass();
        probeUpdatePass = new DDGIProbeUpdatePass();
        indirectLightPass = new DDGIIndirectLightPass();

        probeTracingPass.renderPassEvent = RenderPassEvent.BeforeRendering + 1;
        probeUpdatePass.renderPassEvent = RenderPassEvent.BeforeRendering + 2;
        indirectLightPass.renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
    }

    private void InitRaytracingAccelerationStructure()
    {
        if (accelerationStructure == null)
        {
            RayTracingAccelerationStructure.RASSettings settings = new RayTracingAccelerationStructure.RASSettings();
            settings.layerMask = ~LayerMask.GetMask("UI");
            settings.managementMode = RayTracingAccelerationStructure.ManagementMode.Automatic;
            settings.rayTracingModeMask = RayTracingAccelerationStructure.RayTracingModeMask.DynamicTransform | RayTracingAccelerationStructure.RayTracingModeMask.Static;
            accelerationStructure = new RayTracingAccelerationStructure(settings);
        }
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        InitRaytracingAccelerationStructure();

        if (volumeDesc != null && atmosphereSettings != null && probeRayTracingShader != null && accelerationStructure != null && probeUpdateShader != null && indirectLightShader != null) 
        {
            probeTracingPass.accelerationStructure = accelerationStructure;
            probeTracingPass.probeRayTracingShader = probeRayTracingShader;
            probeTracingPass.volumeDesc = volumeDesc;
            probeTracingPass.atmosphereSettings = atmosphereSettings;
            probeTracingPass.CreateRayDataTexture();

            probeUpdatePass.probeUpdateShader = probeUpdateShader;
            probeUpdatePass.volumeDesc = volumeDesc;
            probeUpdatePass.CreateTexture();

            probeTracingPass.probeIrradianceTexIdentifier = probeUpdatePass.probeIrradianceTexIdentifier;
            probeTracingPass.probeDistanceTexIdentifier = probeUpdatePass.probeDistanceTexIdentifier;
            probeUpdatePass.rayDataTexIdentifier = probeTracingPass.rayDataTexIdentifier;

            indirectLightPass.indirectLightMaterial = CoreUtils.CreateEngineMaterial(indirectLightShader);
            indirectLightPass.probeIrradianceTexIdentifier = probeUpdatePass.probeIrradianceTexIdentifier;
            indirectLightPass.probeDistanceTexIdentifier = probeUpdatePass.probeDistanceTexIdentifier;
            indirectLightPass.volumeDesc = volumeDesc;

            renderer.EnqueuePass(probeTracingPass);
            renderer.EnqueuePass(probeUpdatePass);
            renderer.EnqueuePass(indirectLightPass);
        }
    }

    protected override void Dispose(bool disposing)
    {
        probeTracingPass.ClearRayDataTexture();
        probeUpdatePass.ClearTexture();
        CoreUtils.Destroy(indirectLightPass.indirectLightMaterial);
    }
}