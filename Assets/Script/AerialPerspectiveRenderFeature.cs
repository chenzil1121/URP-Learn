using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class AerialPerspectiveRenderFeature : ScriptableRendererFeature
{
    class AerialPerspectiveRenderPass : ScriptableRenderPass
    {
        public Material m_aerialPerspectiveMaterial;

        RenderTargetHandle tempRTHandle;
        RenderTargetIdentifier blitSrc;

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            RenderTextureDescriptor rtDesc = renderingData.cameraData.cameraTargetDescriptor;
            cmd.GetTemporaryRT(tempRTHandle.id, rtDesc);

            blitSrc = renderingData.cameraData.renderer.cameraColorTarget;
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get(name: "AerialPerspective");
            RenderTargetIdentifier tempRT = tempRTHandle.Identifier();

            cmd.Blit(blitSrc, tempRT, m_aerialPerspectiveMaterial);
            cmd.Blit(tempRT, blitSrc);

            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            cmd.ReleaseTemporaryRT(tempRTHandle.id);
        }
    }

    AerialPerspectiveRenderPass m_ScriptablePass;
    public Shader aerialPerspectiveShader;

    public override void Create()
    {
        m_ScriptablePass = new AerialPerspectiveRenderPass();

        m_ScriptablePass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        m_ScriptablePass.m_aerialPerspectiveMaterial = CoreUtils.CreateEngineMaterial(aerialPerspectiveShader);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_ScriptablePass);
    }

    protected override void Dispose(bool disposing)
    {
        CoreUtils.Destroy(m_ScriptablePass.m_aerialPerspectiveMaterial);
    }
}
