using System.Collections;
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;
using System;

[Serializable]
[CreateAssetMenu(fileName = "DDGIVolumeSettings", menuName = "CZL/DDGIVolumeSettings")]
public class DDGIVolumeDesc : ScriptableObject
{
    //Volume的中心
    [SerializeField]
    public Vector3 origin;
    //Probe的间距
    [SerializeField]
    public Vector3 probeSpacing;
    //每个轴Probe的数量
    [SerializeField]
    public Vector3Int probeCounts;
    //Probe的旋转角度
    [SerializeField]
    public Vector3 probeRotation;
    //Probe的可视化的大小
    [SerializeField]
    public Vector3 probeVisualizationScale;

    //每次TraceProbe时候随机的光线旋转方向
    public Vector4 probeRayRotation;

    //每个Probe光线数量
    [SerializeField]
    public int probeNumRays;
    //每个Probe八面体映射的Irradiance纹理长宽（不包括边界）
    [SerializeField]
    public int probeNumIrradianceInteriorTexels;
    //每个Probe八面体映射的Distance纹理长宽（不包括边界）
    [SerializeField]
    public int probeNumDistanceInteriorTexels;

    //历史数据的lerp系数
    [SerializeField]
    public float probeHysteresis;
    //最大TraceProbe距离
    [SerializeField]
    public float probeMaxRayDistance;

    //计算irradiance时候表面的法线偏移
    [SerializeField]
    public float probeNormalBias;
    //计算irradiance时候表面的视线偏移
    [SerializeField]
    public float probeViewBias;
    
    //float probeDistanceExponent;
    
    [SerializeField]
    public float probeIrradianceEncodingGamma = 5.0f;

    /*
    float probeIrradianceThreshold = 0.25f;
    float probeBrightnessThreshold = 0.10f;
    */

    //Probe的总数，用于索引计数
    public int GetProbeCount()
    {
        return probeCounts.x * probeCounts.y * probeCounts.z;
    }

    //根据Probe索引找到Grid空间的坐标
    public Vector3Int GetProbeCoords(int probeIndex)
    {
        Vector3Int probeCoords = Vector3Int.zero;
        probeCoords.x = probeIndex % probeCounts.x;
        probeCoords.y = probeIndex / (probeCounts.x * probeCounts.z);
        probeCoords.z = (probeIndex / probeCounts.x) % probeCounts.z;

        return probeCoords;
    }

    //根据Grid空间的坐标得到世界空间下的位置
    public Vector3 GetProbeWorldPosition(Vector3Int probeCoords)
    {

        Vector3 probeGridWorldPosition = Vector3.Scale((Vector3)probeCoords, probeSpacing);
        Vector3 probeGridShift = Vector3.Scale(probeSpacing, (Vector3)(probeCounts - Vector3Int.one)) * 0.5f;
        Vector3 probeWorldPosition = probeGridWorldPosition - probeGridShift;
        probeWorldPosition += origin;
        return probeWorldPosition;
    }

    //根据Grid空间的坐标得到世界空间下的位置
    public Matrix4x4 GetProbeWorldMatrix(Vector3Int probeCoords)
    {
        Vector3 probeWorldPosition = GetProbeWorldPosition(probeCoords);
        return Matrix4x4.TRS(probeWorldPosition, Quaternion.identity, probeVisualizationScale);
    }

    Unity.Mathematics.float4 RotationMatrixToQuaternion(Unity.Mathematics.float3x3 m)
    {
        Unity.Mathematics.float4 q = new Unity.Mathematics.float4(0f, 0f, 0f, 0f);

        float m00 = m.c0.x, m01 = m.c0.y, m02 = m.c0.z;
        float m10 = m.c1.x, m11 = m.c1.y, m12 = m.c1.z;
        float m20 = m.c2.x, m21 = m.c2.y, m22 = m.c2.z;
        float diagSum = m00 + m11 + m22;

        if (diagSum > 0f)
        {
            q.w = Mathf.Sqrt(diagSum + 1f) * 0.5f;
            float f = 0.25f / q.w;
            q.x = (m21 - m12) * f;
            q.y = (m02 - m20) * f;
            q.z = (m10 - m01) * f;
        }
        else if ((m00 > m11) && (m00 > m22))
        {
            q.x = Mathf.Sqrt(m00 - m11 - m22 + 1f) * 0.5f;
            float f = 0.25f / q.x;
            q.y = (m10 + m01) * f;
            q.z = (m02 + m20) * f;
            q.w = (m21 - m12) * f;
        }
        else if (m11 > m22)
        {
            q.y = Mathf.Sqrt(m11 - m00 - m22 + 1f) * 0.5f;
            float f = 0.25f / q.y;
            q.x = (m10 + m01) * f;
            q.z = (m21 + m12) * f;
            q.w = (m02 - m20) * f;
        }
        else
        {
            q.z = Mathf.Sqrt(m22 - m00 - m11 + 1f) * 0.5f;
            float f = 0.25f / q.z;
            q.x = (m02 + m20) * f;
            q.y = (m21 + m12) * f;
            q.w = (m10 - m01) * f;
        }
        return q;
    }

    //随机化probeRayRotation
    public void ComputeRandomRotation()
    {
        // This approach is based on James Arvo's implementation from Graphics Gems 3 (pg 117-120).
        // Also available at: http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.53.1357&rep=rep1&type=pdf

        // Setup a random rotation matrix using 3 uniform RVs
        const float RTXGI_2PI = 6.2831853071795864f;
        float u1 = 2f * Mathf.PI * UnityEngine.Random.value;
        float cos1 = Mathf.Cos(u1);
        float sin1 = Mathf.Sin(u1);

        float u2 = RTXGI_2PI * UnityEngine.Random.value;
        float cos2 = Mathf.Cos(u2);
        float sin2 = Mathf.Sin(u2);

        float u3 = UnityEngine.Random.value;
        float sq3 = 2f * Mathf.Sqrt(u3 * (1f - u3));

        float s2 = 2f * u3 * sin2 * sin2 - 1f;
        float c2 = 2f * u3 * cos2 * cos2 - 1f;
        float sc = 2f * u3 * sin2 * cos2;

        // Create the random rotation matrix
        float _11 = cos1 * c2 - sin1 * sc;
        float _12 = sin1 * c2 + cos1 * sc;
        float _13 = sq3 * cos2;

        float _21 = cos1 * sc - sin1 * s2;
        float _22 = sin1 * sc + cos1 * s2;
        float _23 = sq3 * sin2;

        float _31 = cos1 * (sq3 * cos2) - sin1 * (sq3 * sin2);
        float _32 = sin1 * (sq3 * cos2) + cos1 * (sq3 * sin2);
        float _33 = 1f - 2f * u3;

        // HLSL is column-major
        Unity.Mathematics.float3x3 transform;
        transform.c0 = new Unity.Mathematics.float3(_11, _12, _13);
        transform.c1 = new Unity.Mathematics.float3(_21, _22, _23);
        transform.c2 = new Unity.Mathematics.float3(_31, _32, _33);

        probeRayRotation = RotationMatrixToQuaternion(transform);
    }
}
