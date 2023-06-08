using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Experimental.GlobalIllumination;

[ExecuteInEditMode]

public class RayMarchSmoke : MonoBehaviour
{
    private ComputeShader smokePainter;
    private RenderTexture cloudCol,cloudMask,cloudDepth,cloudAlpha;
    private Material composite;
    private int screenW, screenH;
    private Camera cam;
    private CloudDrawer drawer;

    private Light mainLight;
    public GameObject testSphere,testSphere2;

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
        composite = new Material(Shader.Find("Hidden/S_Composit"));
        smokePainter = (ComputeShader)Resources.Load("SmokePainter");
        mainLight = GameObject.Find("Directional Light").GetComponent<Light>();
        screenW = Screen.width;
        screenH = Screen.height;
    }

    private void CreateTexture(int width, int height)
    {
        cloudCol = new RenderTexture(width, height, 0,RenderTextureFormat.ARGB64,RenderTextureReadWrite.Linear);
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
        if (screenH != cam.pixelHeight || screenW != cam.pixelWidth)
        {
            screenW = Screen.width;
            screenH = Screen.height;
            CreateTexture(screenW,screenH);
        }
    }

    
    private void OnRenderImage(RenderTexture src, RenderTexture dest)
    {
        if (!testSphere || !testSphere2)
        {
            Graphics.Blit(src,dest);
            return;
        }

        Vector3 testPos = testSphere.transform.position;
        float testRadius = testSphere.transform.localScale.x;
        CheckResolution();
        Matrix4x4 camProj = GL.GetGPUProjectionMatrix(cam.projectionMatrix, false);
       
        smokePainter.SetFloat( "_ScreenWidth",screenW);
        smokePainter.SetFloat("_ScreenHeight",screenH);
        smokePainter.SetMatrix( "_CamInvProjection",camProj.inverse);
        smokePainter.SetMatrix( "_CamToWorld",cam.cameraToWorldMatrix);
        smokePainter.SetMatrix( "_Unity_VP",camProj * cam.worldToCameraMatrix);
        smokePainter.SetVector("_CamPosWS",cam.transform.position);
        smokePainter.SetVector("_SphereCenter",new Vector4(testPos.x,testPos.y,testPos.z,0));
        smokePainter.SetFloat("_SphereRadius",testRadius/2);
        smokePainter.SetVector("_LightDirection", mainLight.transform.forward);
        smokePainter.SetFloat("_BlendFactor",blendFactor);

       

        
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
        cloudCol.Release();
        cloudMask.Release();
    }
}
