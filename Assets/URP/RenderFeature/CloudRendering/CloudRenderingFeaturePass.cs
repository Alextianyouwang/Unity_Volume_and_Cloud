using Mono.Cecil;
using System;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.RenderGraphModule.Util;
using UnityEngine.Rendering.Universal;
using static Unity.Burst.Intrinsics.X86.Avx;


namespace Experimental.Rendering.CloudRendering
{
    public class CloudRenderingFeaturePass : ScriptableRenderPass
    {
        private Material _cloudRenderMaterial;
        public CloudRenderingFeaturePass(string name)
        {
            profilingSampler = new ProfilingSampler(name);
        }

        public void SetupMembers(CloudRenderingFeatureSettings settings)
        {
            _cloudRenderMaterial = settings.CloudRenderingMaterial;
        }

        // if render graph is not used, use the code below

        //public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        //{
        //    var camTargetDesc = renderingData.cameraData.cameraTargetDescriptor;
        //    // this insures we are passing in a proper Color descriptor, otherwise the format could be a depth format...
        //    camTargetDesc.depthBufferBits = 0;
        //    RenderingUtils.ReAllocateIfNeeded(ref _copiedColor, camTargetDesc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_TempColor");
        //}
        //
        //public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        //{
        //    ref var cameraData = ref renderingData.cameraData;
        //    CommandBuffer cmd = CommandBufferPool.Get();
        //
        //    using (new ProfilingScope(cmd, profilingSampler))
        //    {
        //        _cloudRenderMaterial.SetTexture("_BlitTexture", cameraData.renderer.cameraColorTargetHandle);
        //        RTHandle camTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;
        //        Blitter.BlitCameraTexture(cmd, camTarget, _copiedColor,_cloudRenderMaterial,0);
        //        Blitter.BlitCameraTexture(cmd, _copiedColor, camTarget);
        //    }
        //    context.ExecuteCommandBuffer(cmd);
        //    cmd.Clear();
        //    CommandBufferPool.Release(cmd);
        //}
        //
        //public void Dispose()
        //{
        //    _copiedColor?.Release();
        //}

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            UniversalResourceData resourcesData = frameData.Get<UniversalResourceData>();
            UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();

            TextureHandle destination;
            TextureDesc targetDesc = renderGraph.GetTextureDesc(resourcesData.cameraColor);
            targetDesc.name = "_CamerColorFullScreenPass";
            targetDesc.clearBuffer = false;
            destination = renderGraph.CreateTexture(targetDesc);

            RenderGraphUtils.BlitMaterialParameters param = new(resourcesData.activeColorTexture, destination, _cloudRenderMaterial, 0);
            renderGraph.AddBlitPass(param , "Cloud Rendering Pass");
            resourcesData.cameraColor = destination;
        }
    }
}
