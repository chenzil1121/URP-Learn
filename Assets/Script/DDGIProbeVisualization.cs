using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class DDGIProbeVisualization : ScriptableRendererFeature
{
    class ProbeVisualizationRenderPass : ScriptableRenderPass
    {
        public DDGIVolumeDesc volumeDesc;
        public Material probeMat;
        public Mesh probeMesh;

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get(name: "DDGI Probe Visualization");

            if (probeMesh != null && probeMat != null)
            {
                int ProbeCount = volumeDesc.GetProbeCount();

                for (int i = 0; i < ProbeCount; i++)
                {
                    Vector3Int probeCoords = volumeDesc.GetProbeCoords(i);
                    Matrix4x4 probeMatrix = volumeDesc.GetProbeWorldMatrix(probeCoords);
                    cmd.DrawMesh(probeMesh, probeMatrix, probeMat);
                }
            }

            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {

        }
    }

    ProbeVisualizationRenderPass m_ScriptablePass;

    public DDGIVolumeDesc volumeDesc;
    public Shader probeShader;
    public Mesh probeMesh;

    /// <inheritdoc/>
    public override void Create()
    {
        m_ScriptablePass = new ProbeVisualizationRenderPass();
        m_ScriptablePass.volumeDesc = volumeDesc;
        m_ScriptablePass.probeMat = CoreUtils.CreateEngineMaterial(probeShader);
        m_ScriptablePass.probeMesh = probeMesh;
        //AfterRenderingPostProcessing�׶�֮��Ҫ��CopyDepth���Ż��CameraDepth Copy��ViewRT(Game����Scene),����Ҫ��CopyDepth֮����룬�ſ���ʹ�õ�ViewRT��Depth
        //com.unity.render-pipelines.universal@12.1.7\Runtime\UniversalRenderer.cs�Ĺ��캯����279��282��
        m_ScriptablePass.renderPassEvent = RenderPassEvent.AfterRendering + 11;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {

        if (renderingData.cameraData.cameraType == CameraType.SceneView)
            renderer.EnqueuePass(m_ScriptablePass);

    }

    protected override void Dispose(bool disposing)
    {
        CoreUtils.Destroy(m_ScriptablePass.probeMat);
    }
}


