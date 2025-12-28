using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

namespace Experimental.Rendering.CloudRendering
{
    class CloudRenderingFeaturePass : ScriptableRenderPass
    {
        private Material _cloudRenderMaterial;
        private RTHandle _copiedColor;
        public CloudRenderingFeaturePass(string name)
        {
            profilingSampler = new ProfilingSampler(name);
        }

        public void SetupMembers(CloudRenderingFeatureSettings settings)
        {
            _cloudRenderMaterial = settings.CloudRenderingMaterial;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var camTargetDesc = renderingData.cameraData.cameraTargetDescriptor;
            // this insures we are passing in a proper Color descriptor, otherwise the format could be a depth format...
            camTargetDesc.depthBufferBits = 0;
            RenderingUtils.ReAllocateIfNeeded(ref _copiedColor, camTargetDesc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_TempColor");
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            ref var cameraData = ref renderingData.cameraData;
            CommandBuffer cmd = CommandBufferPool.Get();

            using (new ProfilingScope(cmd, profilingSampler))
            {
                _cloudRenderMaterial.SetTexture("_BlitTexture", cameraData.renderer.cameraColorTargetHandle);
                RTHandle camTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;
                Blitter.BlitCameraTexture(cmd, camTarget, _copiedColor,_cloudRenderMaterial,0);
                Blitter.BlitCameraTexture(cmd, _copiedColor, camTarget);
            }
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }

        public void Dispose()
        {
            _copiedColor?.Release();
        }



        // Render graph related
        private class PassData
        {
            public TextureHandle InputTexture;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            UniversalResourceData resourcesData = frameData.Get<UniversalResourceData>();
            UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();
        
            TextureHandle source, destination;
        
            Debug.Assert(resourcesData.cameraColor.IsValid());
        
            TextureDesc targetDesc = renderGraph.GetTextureDesc(resourcesData.cameraColor);
            targetDesc.name = "_CamerColorFullScreenPass";
            targetDesc.clearBuffer = false;
        
            source = resourcesData.activeColorTexture;
            destination = renderGraph.CreateTexture(targetDesc);
        
            const string passName = "Cloud Rendering Pass";
        
            using (var builder = renderGraph.AddRasterRenderPass<PassData>(passName, out var passData, profilingSampler))
            {
                passData.InputTexture = source;
                builder.UseTexture(passData.InputTexture, AccessFlags.Read);
                builder.SetRenderAttachment(destination, 0, AccessFlags.Write);
                builder.SetRenderFunc((PassData data, RasterGraphContext rgContext) =>
                {
                    Blitter.BlitTexture(rgContext.cmd, _copiedColor, new Vector4(1, 1, 0, 0), _cloudRenderMaterial, 0);
                });
            }
        }
    }
}
