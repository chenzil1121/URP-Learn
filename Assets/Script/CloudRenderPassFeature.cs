using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class CloudRenderPassFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Setting
    {
        //体积云材质
        public Material CloudMaterial;
        //渲染的时间点
        public RenderPassEvent CloudRenderPassEvent;
    }

    class CloudRenderPass : ScriptableRenderPass
    {
        public CloudRenderPass(Setting set)
        {
            setting = set;
            renderPassEvent = setting.CloudRenderPassEvent;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            width = renderingData.cameraData.cameraTargetDescriptor.width;
            height = renderingData.cameraData.cameraTargetDescriptor.height;
            cameraColorTex = renderingData.cameraData.renderer.cameraColorTarget;

            setting.CloudMaterial.SetVector("_BlueNoiseTexUV", new Vector4((float)width / (float)512, (float)width / (float)512, 0, 0));
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get(name: "CloudRenderPass");

            //创建临时渲染纹理
            RenderTextureDescriptor temDescriptor = new RenderTextureDescriptor(width, height, RenderTextureFormat.ARGB32);
            temDescriptor.depthBufferBits = 0;
            int temTextureID = Shader.PropertyToID("_CloudTex");
            cmd.GetTemporaryRT(temTextureID, temDescriptor);

            
            cmd.Blit(cameraColorTex, temTextureID, setting.CloudMaterial, 0);
            cmd.Blit(temTextureID, cameraColorTex, setting.CloudMaterial, 1);

            //cmd.DrawMesh(RenderingUtils.fullscreenMesh, Matrix4x4.identity, setting.CloudMaterial);
            

            //执行
            context.ExecuteCommandBuffer(cmd);
            //释放资源
            cmd.ReleaseTemporaryRT(temTextureID);

            CommandBufferPool.Release(cmd);
        }


        public override void OnCameraCleanup(CommandBuffer cmd)
        {
        }

        public RenderTargetIdentifier cameraColorTex;
        public int width;
        public int height;

        private Setting setting;
    }

    CloudRenderPass cloudPass;
    public Setting setting = new Setting();

    public override void Create()
    {
        cloudPass = new CloudRenderPass(setting);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (!(setting.CloudMaterial && (renderingData.cameraData.cameraType == CameraType.Game || renderingData.cameraData.cameraType == CameraType.SceneView)))
            return;
        
        renderer.EnqueuePass(cloudPass);
    }
}


