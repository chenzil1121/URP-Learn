using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class CloudNoiseGenerator : MonoBehaviour
{
    const int computeThreadGroupSize = 8;
    const int slicerThreadGroupSize = 32;
    public const string detailNoiseName = "DetailNoise";
    public const string BasicNoiseName = "BasicNoise";

    [Header("Noise Settings")]
    public int basicNoiseResolution = 128;
    public int detailNoiseResolution = 64;

    public ComputeShader noiseCompute;
    public ComputeShader slicer;

    [SerializeField, HideInInspector]
    public RenderTexture basicNoiseTexture;
    [SerializeField, HideInInspector]
    public RenderTexture detailNoiseTexture;

    public void CreateTexture(ref RenderTexture texture, int resolution, string name)
    {
        var format = UnityEngine.Experimental.Rendering.GraphicsFormat.R8_UNorm;
        if (texture == null)
        {
            Debug.Log("Create tex: " + name);

            texture = new RenderTexture(resolution, resolution, 0);
            texture.graphicsFormat = format;
            texture.volumeDepth = resolution;
            texture.enableRandomWrite = true;
            texture.dimension = UnityEngine.Rendering.TextureDimension.Tex3D;
            texture.name = name;

            texture.Create();
        }
        texture.wrapMode = TextureWrapMode.Repeat;
        texture.filterMode = FilterMode.Bilinear;
    }

    public void UpdateNoise()
    {
        CreateTexture(ref basicNoiseTexture, basicNoiseResolution, BasicNoiseName);
        CreateTexture(ref detailNoiseTexture, detailNoiseResolution, detailNoiseName);

        if (noiseCompute)
        {
            int numThreadGroups = Mathf.CeilToInt(basicNoiseResolution / (float)computeThreadGroupSize);
            noiseCompute.SetTexture(0, "Result", basicNoiseTexture);
            noiseCompute.Dispatch(0,numThreadGroups, numThreadGroups, basicNoiseResolution);
            numThreadGroups = Mathf.CeilToInt(detailNoiseResolution / (float)computeThreadGroupSize);
            noiseCompute.SetTexture(1, "Result", detailNoiseTexture);
            noiseCompute.Dispatch(1, numThreadGroups, numThreadGroups, detailNoiseResolution);

            Save(basicNoiseTexture, "basicNoiseTexture");
            Save(detailNoiseTexture, "detailNoiseTexture");
        }
        
    }

    public void Save(RenderTexture volumeTexture, string saveName)
    {
        int resolution = volumeTexture.width;
        Texture2D[] slices = new Texture2D[resolution];

        slicer.SetTexture(0, "volumeTexture", volumeTexture);

        for (int layer = 0; layer < resolution; layer++)
        {
            var slice = new RenderTexture(resolution, resolution, 0);
            slice.dimension = UnityEngine.Rendering.TextureDimension.Tex2D;
            slice.graphicsFormat = UnityEngine.Experimental.Rendering.GraphicsFormat.R8_UNorm;
            slice.enableRandomWrite = true;
            slice.Create();

            slicer.SetTexture(0, "slice", slice);
            slicer.SetInt("layer", layer);
            int numThreadGroups = Mathf.CeilToInt(resolution / (float)slicerThreadGroupSize);
            slicer.Dispatch(0, numThreadGroups, numThreadGroups, 1);

            slices[layer] = ConvertFromRenderTexture(slice);
        }

        var x = Tex3DFromTex2DArray(slices, resolution);
#if UNITY_EDITOR
        UnityEditor.AssetDatabase.CreateAsset(x, "Assets/Texture/" + saveName + ".asset");
#endif
    }

    Texture3D Tex3DFromTex2DArray(Texture2D[] slices, int resolution)
    {
        Texture3D tex3D = new Texture3D(resolution, resolution, resolution, TextureFormat.R8, false);
        tex3D.filterMode = FilterMode.Bilinear;
        tex3D.wrapMode = TextureWrapMode.Repeat;

        Color[] outputPixels = tex3D.GetPixels();

        for (int z = 0; z < resolution; z++)
        {
            Color[] layerPixels = slices[z].GetPixels();
            for (int x = 0; x < resolution; x++)
                for (int y = 0; y < resolution; y++)
                {
                    outputPixels[x + resolution * (y + z * resolution)] = layerPixels[x + y * resolution];
                }
        }

        tex3D.SetPixels(outputPixels);
        tex3D.Apply();

        return tex3D;
    }

    Texture2D ConvertFromRenderTexture(RenderTexture rt)
    {
        Texture2D output = new Texture2D(rt.width, rt.height);
        RenderTexture.active = rt;
        output.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0);
        output.Apply();
        return output;
    }

}
