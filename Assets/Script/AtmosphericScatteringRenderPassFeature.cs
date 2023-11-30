using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class AtmosphericScatteringRenderPassFeature : ScriptableRendererFeature
{
    class AtmosphericScatteringRenderPass : ScriptableRenderPass
    {
        RenderTexture m_atmosphericScatteringLut;
        RenderTexture m_transmittanceLut;
        RenderTexture m_multiScatteringLut;
        RenderTexture m_aerialPerspectiveLut;

        public Material atmosphericScatteringLutMaterial;
        public Material transmittanceLutMaterial;
        public Material multiScatteringLutMaterial;
        public Material aerialPerspectiveLutMaterial;

        public AtmosphereSettings atmosphereSettings;
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            m_atmosphericScatteringLut = RenderTexture.GetTemporary(256, 128, 0, RenderTextureFormat.ARGBFloat);
            atmosphereSettings.AtmosphericScatteringLut = new RenderTargetIdentifier(m_atmosphericScatteringLut);
            m_transmittanceLut = RenderTexture.GetTemporary(256, 64, 0, RenderTextureFormat.ARGBFloat);
            m_multiScatteringLut = RenderTexture.GetTemporary(32, 32, 0, RenderTextureFormat.ARGBFloat);
            m_aerialPerspectiveLut = RenderTexture.GetTemporary(32 * 32, 32, 0, RenderTextureFormat.ARGBFloat);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get(name: "PreComputeAtmosphericScattering");

            cmd.SetGlobalTexture("_atmosphericScatteringLut", m_atmosphericScatteringLut);
            cmd.SetGlobalTexture("_transmittanceLut", m_transmittanceLut);
            cmd.SetGlobalTexture("_multiScatteringLut", m_multiScatteringLut);
            cmd.SetGlobalTexture("_aerialPerspectiveLut", m_aerialPerspectiveLut);
            cmd.SetGlobalColor("_GroundColor", atmosphereSettings.GroundColor);
            cmd.SetGlobalFloat("_PlanetRadius", atmosphereSettings.PlanetRadius);
            cmd.SetGlobalFloat("_AtmosphereHeight", atmosphereSettings.AtmosphereHeight);
            cmd.SetGlobalFloat("_SunLightIntensity", atmosphereSettings.SunLightIntensity);
            cmd.SetGlobalColor("_SunLightColor", atmosphereSettings.SunLightColor);
            cmd.SetGlobalFloat("_SunDiskSize", atmosphereSettings.SunDiskSize);
            cmd.SetGlobalFloat("_RayleighScatteringScale", atmosphereSettings.RayleighScatteringScale);
            cmd.SetGlobalFloat("_RayleighScatteringScalarHeight", atmosphereSettings.RayleighScatteringScalarHeight);
            cmd.SetGlobalFloat("_MieScatteringScale", atmosphereSettings.MieScatteringScale);
            cmd.SetGlobalFloat("_MieAnisotropy", atmosphereSettings.MieAnisotropy);
            cmd.SetGlobalFloat("_MieScatteringScalarHeight", atmosphereSettings.MieScatteringScalarHeight);
            cmd.SetGlobalFloat("_OzoneAbsorptionScale", atmosphereSettings.OzoneAbsorptionScale);
            cmd.SetGlobalFloat("_OzoneLevelCenterHeight", atmosphereSettings.OzoneLevelCenterHeight);
            cmd.SetGlobalFloat("_OzoneLevelWidth", atmosphereSettings.OzoneLevelWidth);
            cmd.SetGlobalFloat("_AerialPerspectiveDistance", atmosphereSettings.AerialPerspectiveDistance);
            cmd.SetGlobalVector("_AerialPerspectiveVoxelSize", new Vector4(32, 32, 32, 0));

            cmd.Blit(null, m_transmittanceLut, transmittanceLutMaterial);
            cmd.Blit(null, m_multiScatteringLut, multiScatteringLutMaterial);
            cmd.Blit(null, m_atmosphericScatteringLut, atmosphericScatteringLutMaterial);
            cmd.Blit(null, m_aerialPerspectiveLut, aerialPerspectiveLutMaterial);

            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            RenderTexture.ReleaseTemporary(m_atmosphericScatteringLut);
            RenderTexture.ReleaseTemporary(m_transmittanceLut);
            RenderTexture.ReleaseTemporary(m_multiScatteringLut);
            RenderTexture.ReleaseTemporary(m_aerialPerspectiveLut);
        }
    }

    AtmosphericScatteringRenderPass m_ScriptablePass;

    public Shader atmosphericScatteringLutShader;
    public Shader transmittanceLutShader;
    public Shader multiScatteringLutShader;
    public Shader aerialPerspectiveLutShader;
    public AtmosphereSettings atmosphereSettings;

    public override void Create()
    {
        m_ScriptablePass = new AtmosphericScatteringRenderPass();

        m_ScriptablePass.renderPassEvent = RenderPassEvent.BeforeRendering;
        m_ScriptablePass.atmosphereSettings = atmosphereSettings;
        m_ScriptablePass.atmosphericScatteringLutMaterial = CoreUtils.CreateEngineMaterial(atmosphericScatteringLutShader);
        m_ScriptablePass.transmittanceLutMaterial = CoreUtils.CreateEngineMaterial(transmittanceLutShader);
        m_ScriptablePass.multiScatteringLutMaterial = CoreUtils.CreateEngineMaterial(multiScatteringLutShader);
        m_ScriptablePass.aerialPerspectiveLutMaterial = CoreUtils.CreateEngineMaterial(aerialPerspectiveLutShader);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_ScriptablePass);
    }

    protected override void Dispose(bool disposing)
    {
        CoreUtils.Destroy(m_ScriptablePass.atmosphericScatteringLutMaterial);
        CoreUtils.Destroy(m_ScriptablePass.transmittanceLutMaterial);
        CoreUtils.Destroy(m_ScriptablePass.multiScatteringLutMaterial);
        CoreUtils.Destroy(m_ScriptablePass.aerialPerspectiveLutMaterial);
    }
}


