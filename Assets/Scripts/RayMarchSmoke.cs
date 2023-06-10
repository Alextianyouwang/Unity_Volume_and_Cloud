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
    private int downScaleFactor_local;


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
        downScaleFactor_local = downScaleFactor;
        screenW = Screen.width/ downScaleFactor_local;
        screenH = Screen.height/ downScaleFactor_local;
        
    }

    private void CreateTexture(int width, int height)
    {
        depthTexture = RenderTexture.GetTemporary(width, height, 0, RenderTextureFormat.ARGB64, RenderTextureReadWrite.Linear);
        

        cloudCol = new RenderTexture(width, height, 0,RenderTextureFormat.ARGB64,RenderTextureReadWrite.sRGB);
        cloudCol.enableRandomWrite = true;
        cloudCol.Create();
        
        cloudMask = new RenderTexture(width, height, 0,RenderTextureFormat.ARGB64,RenderTextureReadWrite.Linear);
        cloudMask.enableRandomWrite = true;
        cloudMask.Create();
        
        cloudDepth = new RenderTexture(width, height, 0,RenderTextureFormat.ARGB64,RenderTextureReadWrite.Linear);
        cloudDepth.enableRandomWrite = true;
        cloudDepth.Create();
        
        cloudAlpha = new RenderTexture(width, height, 0,RenderTextureFormat.ARGB64,RenderTextureReadWrite.Linear);
        cloudAlpha.enableRandomWrite = true;
        cloudAlpha.Create();
        
    }

    private void CheckResolution()
    {
        if (screenH != Screen.height / downScaleFactor_local
            || screenW != Screen.width / downScaleFactor_local
            || downScaleFactor_local != downScaleFactor
           )
        {
            downScaleFactor_local = downScaleFactor;
            screenW = Screen.width/downScaleFactor_local;
            screenH = Screen.height/downScaleFactor_local;
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

        smokePainter.SetTexture(0, "_DepthTextureRT", depthTexture);
        smokePainter.SetTexture(0,"_CloudColRT",cloudCol);
        smokePainter.SetTexture(0,"_CloudMaskRT",cloudMask);
        smokePainter.SetTexture(0,"_CloudDepthRT",cloudDepth);
        smokePainter.SetTexture(0,"_CloudAlphaRT",cloudAlpha);
        if (drawer!= null && drawer.GetSphereBuffer()!= null)
        {
            smokePainter.SetInt("_SphereCount",drawer.GetMaxSphereNumber());
            smokePainter.SetBuffer(0,"_SphereBuffer",drawer.GetSphereBuffer());
            smokePainter.Dispatch(0,Mathf.CeilToInt(screenW/8f), Mathf.CeilToInt(screenH/8f),1);

        }
        
        composite.SetTexture("_MainTex",src);
        composite.SetTexture("_CloudCol",cloudCol);
        composite.SetTexture("_CloudMask",cloudMask);
        composite.SetTexture("_CloudDepth",cloudDepth);
        composite.SetTexture("_CloudAlpha",cloudAlpha);
        Graphics.Blit(src,dest,composite);
        
    }

    private void OnDisable()
    {
        
        depthTexture.Release();
        
        cloudCol.Release();
        cloudMask.Release();
        cloudDepth.Release();
        cloudAlpha.Release();
    }
}
