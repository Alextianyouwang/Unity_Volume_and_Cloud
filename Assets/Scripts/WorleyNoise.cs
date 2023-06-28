using Microsoft.Win32.SafeHandles;
using System;
using System.Collections;
using System.Collections.Generic;
using System.Net.NetworkInformation;
using UnityEngine;

[ExecuteInEditMode]
public class WorleyNoise : MonoBehaviour
{
    private ComputeShader noiseGenerator;
    private RenderTexture noiseTexture;
    public int Resolution = 128;
    private int resolution;

    public Material displayMaterial;
    private void OnEnable()
    {
        Init();
    }
    private void OnDisable()
    {
        noiseTexture.Release();
    }

    private void Update()
    {
        CheckResolution();
        UpdateComputeShader();
        UpdateMaterial();
    }

    private void CheckResolution() 
    {
        if (resolution != Resolution && Resolution > 0) 
        {
            EnableRT(Resolution);
            resolution = Resolution;
        }

    }
    private void Init()
    {
        noiseGenerator = (ComputeShader)Resources.Load("CS_WorleyNoise");
        resolution = Resolution;
        EnableRT(Resolution);
    }
    private void EnableRT(int _resolution) 
    {
        noiseTexture = RenderTexture.GetTemporary(_resolution, _resolution, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.Linear);
        noiseTexture.enableRandomWrite = true;
        noiseTexture.filterMode = FilterMode.Point;
        noiseTexture.Create();
    }
    private void UpdateComputeShader()
    {
        if (Resolution < 8)
            return;
        noiseGenerator.SetTexture(0, "_NoiseRT", noiseTexture);
        noiseGenerator.SetInt("_Resolution", Resolution);
        noiseGenerator.Dispatch(0, Mathf.CeilToInt(Resolution / 8) , Mathf.CeilToInt(Resolution / 8), 1);
    }

    private void UpdateMaterial() 
    {
        if (!displayMaterial)
            return;

        displayMaterial.SetTexture("_MainTex", noiseTexture);
    }
}
