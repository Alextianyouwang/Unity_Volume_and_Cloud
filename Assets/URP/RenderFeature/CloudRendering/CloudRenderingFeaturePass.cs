using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.RenderGraphModule.Util;
using UnityEngine.Rendering.Universal;

namespace Experimental.Rendering.CloudRendering
{
    public class CloudRenderingFeaturePass : ScriptableRenderPass
    {
        private CloudRenderingFeatureSettings _settings;
        public CloudRenderingFeaturePass(string name)
        {
            profilingSampler = new ProfilingSampler(name);
        }

        public void SetupMembers(CloudRenderingFeatureSettings settings)
        {
            _settings = settings;
        }

        private class PassData
        {
            public Material material;
            public TextureHandle sourceTexture;
            public TextureHandle depthTexture;
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

            _settings.CloudRenderingMaterial.SetMatrix("_CameraInverseViewMatrix", cameraData.camera.projectionMatrix.inverse);
            _settings.CloudRenderingMaterial.SetVector("_BoxMin", _settings.BoxMin);
            _settings.CloudRenderingMaterial.SetVector("_BoxMax", _settings.BoxMax);
            _settings.CloudRenderingMaterial.SetFloat("_Camera_Near", cameraData.camera.nearClipPlane);
            _settings.CloudRenderingMaterial.SetFloat("_Camera_Far", cameraData.camera.farClipPlane);


            using (var builder = renderGraph.AddRasterRenderPass<PassData>("Cloud Rendering Pass", out var passData, profilingSampler))
            {
                passData.material = _settings.CloudRenderingMaterial;
                passData.sourceTexture = resourcesData.activeColorTexture;
                passData.depthTexture = resourcesData.cameraDepthTexture;

                builder.UseTexture(passData.sourceTexture);
                builder.UseTexture(passData.depthTexture);
                builder.SetRenderAttachment(destination, 0);

                builder.SetRenderFunc((PassData data, RasterGraphContext context) =>
                {
                    // Bind depth texture to material
                    data.material.SetTexture("_CameraDepthTexture", data.depthTexture);

                    // Draw fullscreen with the source as main texture
                    Blitter.BlitTexture(context.cmd, data.sourceTexture, new Vector4(1, 1, 0, 0), data.material, 0);
                });
            }

            resourcesData.cameraColor = destination;
        }
    }
}
