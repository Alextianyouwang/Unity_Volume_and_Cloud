using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

namespace Experimental.Rendering.CloudRendering
{
    public class CloudRenderingFeaturePass : ScriptableRenderPass
    {
        private CloudRenderingFeatureSettings _settings;
        
        // Maximum number of volumetric lights we support
        private const int MaxVolumetricLights = 8;
        
        // Arrays to pass to shader
        private Vector4[] _lightPositions = new Vector4[MaxVolumetricLights];
        private Vector4[] _lightColors = new Vector4[MaxVolumetricLights];
        private float[] _lightRanges = new float[MaxVolumetricLights];
        
        // Shader property IDs
        private static readonly int _VolumetricLightCount = Shader.PropertyToID("_VolumetricLightCount");
        private static readonly int _VolumetricLightPositions = Shader.PropertyToID("_VolumetricLightPositions");
        private static readonly int _VolumetricLightColors = Shader.PropertyToID("_VolumetricLightColors");
        private static readonly int _VolumetricLightRanges = Shader.PropertyToID("_VolumetricLightRanges");
        
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
            UniversalLightData lightData = frameData.Get<UniversalLightData>();

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

            // Manually collect additional lights for volumetric rendering
            SetupVolumetricLights(lightData);

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
        
        private void SetupVolumetricLights(UniversalLightData lightData)
        {
            int lightCount = 0;
            var visibleLights = lightData.visibleLights;
            
            // Skip index 0 which is the main light
            for (int i = 1; i < visibleLights.Length && lightCount < MaxVolumetricLights; i++)
            {
                var visibleLight = visibleLights[i];
                
                // Only include point and spot lights for volumetrics
                if (visibleLight.lightType == LightType.Point || visibleLight.lightType == LightType.Spot)
                {
                    var light = visibleLight.light;
                    if (light == null) continue;
                    
                    _lightPositions[lightCount] = light.transform.position;
                    _lightColors[lightCount] = new Vector4(
                        light.color.r * light.intensity,
                        light.color.g * light.intensity,
                        light.color.b * light.intensity,
                        1.0f
                    );
                    _lightRanges[lightCount] = light.range;
                    lightCount++;
                }
            }
            
            _settings.CloudRenderingMaterial.SetInt(_VolumetricLightCount, lightCount);
            _settings.CloudRenderingMaterial.SetVectorArray(_VolumetricLightPositions, _lightPositions);
            _settings.CloudRenderingMaterial.SetVectorArray(_VolumetricLightColors, _lightColors);
            _settings.CloudRenderingMaterial.SetFloatArray(_VolumetricLightRanges, _lightRanges);
        }
    }
}
