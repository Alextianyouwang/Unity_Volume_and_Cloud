using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Experimental.GlobalIllumination;
using UnityEngine.Rendering;

//[ExecuteInEditMode]

public class RayMarchSmoke : MonoBehaviour
{
    private ComputeShader smokePainter;
    private CommandBuffer depthBuffer;
    private RenderTexture cloudCol,cloudMask,cloudDepth,cloudAlpha,depthTexture;
    private Material composite;
    private int screenW, screenH;
    private Camera cam;
    private CloudDrawer drawer;

    private Light mainLight;

    [Range(1,4)]
    public int downScaleFactor = 2;
    private int downScaleFactorLocal;

    [Header("Cloud Color")]
    [ColorUsage(true,true)] 
    public Color cloudColor;

    [Header("Ray Marching Setting")] 
    [Range(0.05f,0.4f)]
    public float eyeSampleStepSize = 0.15f;
    [Range(0,8)]
    public int lightSampleCount = 5;
    [Range(0.05f,0.5f)]
    public float lightStepSize = 0.15f;

    [Header("Lighting Setting" )]
    [Range(0,300)]
    public float cloudDensity= 200;
    [Range(0,300)]
    public float cloudAbsorbance = 200;
    [Range(0,300)]
    public float lightIntensity = 200;

    [Header("Shape Blend Setting" )]
    [Range(0, 1)] public float blendFactor = 0.5f;
    
    private void OnEnable()
    {
        Initialize();
        CreateTexture(screenW,screenH);
    }

    private void Initialize()
    {
        cam = GetComponent<Camera>();
        drawer = GetComponent<CloudDrawer>();
        composite = new Material(Shader.Find("Hidden/S_Composite"));
        smokePainter = (ComputeShader)Resources.Load("CS_Cloud");
        mainLight = GameObject.Find("Directional Light").GetComponent<Light>();
        downScaleFactorLocal = downScaleFactor;
        screenW = cam.pixelWidth/ downScaleFactorLocal;
        screenH = cam.pixelHeight/ downScaleFactorLocal;
        
    }

    private void CreateTexture(int width, int height)
    {
        depthTexture = RenderTexture.GetTemporary(cam.pixelWidth, cam.pixelHeight, 0, RenderTextureFormat.ARGB64, RenderTextureReadWrite.Linear);
        depthTexture.filterMode = FilterMode.Point;

        cloudCol = RenderTexture.GetTemporary(width, height, 0,RenderTextureFormat.ARGB64,RenderTextureReadWrite.sRGB);
        cloudCol.enableRandomWrite = true;
        depthTexture.filterMode = FilterMode.Point;
        cloudCol.Create();
        
        /*cloudMask = new RenderTexture(width, height, 0,RenderTextureFormat.ARGB64,RenderTextureReadWrite.Linear);
        cloudMask.enableRandomWrite = true;
        cloudMask.Create();
        
        cloudDepth = new RenderTexture(width, height, 0,RenderTextureFormat.ARGB64,RenderTextureReadWrite.Linear);
        cloudDepth.enableRandomWrite = true;
        cloudDepth.Create();
        
        cloudAlpha = new RenderTexture(width, height, 0,RenderTextureFormat.ARGB64,RenderTextureReadWrite.Linear);
        cloudAlpha.enableRandomWrite = true;
        cloudAlpha.Create();*/
        
    }

    private void CheckResolution()
    {
        if (screenH != cam.pixelHeight / downScaleFactorLocal
            || screenW != cam.pixelWidth / downScaleFactorLocal
            || downScaleFactorLocal != downScaleFactor
           )
        {
            downScaleFactorLocal = downScaleFactor;
            screenW = cam.pixelWidth/downScaleFactorLocal;
            screenH = cam.pixelHeight/downScaleFactorLocal;
            CreateTexture(screenW,screenH);
        }
    }

    
    private void OnRenderImage(RenderTexture src, RenderTexture dest)
    {
        CheckResolution();
        Matrix4x4 camProj = GL.GetGPUProjectionMatrix(cam.projectionMatrix, false);

        depthBuffer = new CommandBuffer();
        depthBuffer.Blit(BuiltinRenderTextureType.Depth, depthTexture);
        Graphics.ExecuteCommandBuffer(depthBuffer);
        depthBuffer.Release();

        smokePainter.SetFloat( "_ScreenWidth",screenW);
        smokePainter.SetFloat("_ScreenHeight",screenH);
        smokePainter.SetMatrix( "_CamInvProjection",camProj.inverse);
        smokePainter.SetMatrix( "_CamToWorld",cam.cameraToWorldMatrix);
        smokePainter.SetMatrix( "_Unity_VP",camProj * cam.worldToCameraMatrix);
        smokePainter.SetMatrix( "_Unity_V",cam.worldToCameraMatrix);
        smokePainter.SetVector("_CamPosWS",cam.transform.position);
        smokePainter.SetVector("_LightDirection", mainLight.transform.forward);
        
        
        smokePainter.SetFloat("_BlendFactor",blendFactor);
        smokePainter.SetFloat("_CloudAbsorbance",cloudAbsorbance);
        smokePainter.SetFloat("_LightIntensity",lightIntensity);
        smokePainter.SetFloat("_CloudDensity",cloudDensity);
        smokePainter.SetFloat("_LightStepSize",lightStepSize);
        smokePainter.SetFloat("_EyeSampleStepSize",eyeSampleStepSize);
        smokePainter.SetInt("_LightSampleCount",lightSampleCount);
        smokePainter.SetVector("_CloudColor", new Vector3(cloudColor.r,cloudColor.g,cloudColor.b));
        Color lightColor = mainLight.color;
        smokePainter.SetVector("_LightColor",new Vector3(lightColor.r,lightColor.g,lightColor.b));


        smokePainter.SetTexture(0, "_DepthTextureRT", depthTexture);
        smokePainter.SetTexture(0,"_CloudColRT",cloudCol);
        //smokePainter.SetTexture(0,"_CloudMaskRT",cloudMask);
        //smokePainter.SetTexture(0,"_CloudDepthRT",cloudDepth);
        //smokePainter.SetTexture(0,"_CloudAlphaRT",cloudAlpha);
        if (drawer!= null && drawer.GetSphereBuffer()!= null)
        {
            smokePainter.SetInt("_SphereCount",drawer.GetMaxSphereNumber());
            smokePainter.SetBuffer(0,"_SphereBuffer",drawer.GetSphereBuffer());
            smokePainter.Dispatch(0,Mathf.CeilToInt(screenW/8f), Mathf.CeilToInt(screenH/8f),1);
        }
        
        composite.SetTexture("_MainTex",src);
        composite.SetTexture("_CloudCol",cloudCol);
        //composite.SetTexture("_CloudMask",cloudMask);
        //composite.SetTexture("_CloudDepth",cloudDepth);
        //composite.SetTexture("_CloudAlpha",cloudAlpha);
        Graphics.Blit(src,dest,composite);
        
    }

    private void OnDisable()
    {
        
        depthTexture.Release();
        
        cloudCol.Release();
        //cloudMask.Release();
        //cloudDepth.Release();
        //cloudAlpha.Release();
    }
}
