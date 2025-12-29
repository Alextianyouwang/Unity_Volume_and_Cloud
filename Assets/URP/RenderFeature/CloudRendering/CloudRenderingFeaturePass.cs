using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.RenderGraphModule.Util;
using UnityEngine.Rendering.Universal;

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
