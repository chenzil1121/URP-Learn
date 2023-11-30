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
        //AfterRenderingPostProcessing阶段之后还要做CopyDepth，才会把CameraDepth Copy到ViewRT(Game或者Scene),所以要在CopyDepth之后插入，才可以使用到ViewRT的Depth
        //com.unity.render-pipelines.universal@12.1.7\Runtime\UniversalRenderer.cs的构造函数中279和282行
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


