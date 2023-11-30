using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;
using System;
using UnityEngine.Rendering;

[Serializable]
[CreateAssetMenu(fileName = "AtmosphereSettings", menuName = "CZL/AtmosphereSettings")]
public class AtmosphereSettings : ScriptableObject
{
    [SerializeField]
    public Color GroundColor = Color.gray;

    [SerializeField]
    public float PlanetRadius = 6360000.0f;

    [SerializeField]
    public float AtmosphereHeight = 60000.0f;

    [SerializeField]
    public float SunLightIntensity = 31.4f;

    [SerializeField]
    public Color SunLightColor = Color.white;

    [SerializeField]
    public float SunDiskSize = 1.0f;

    [SerializeField]
    public float RayleighScatteringScale = 1.0f;

    [SerializeField]
    public float RayleighScatteringScalarHeight = 8000.0f;

    [SerializeField]
    public float MieScatteringScale = 1.0f;

    [SerializeField]
    public float MieAnisotropy = 0.8f;

    [SerializeField]
    public float MieScatteringScalarHeight = 1200.0f;

    [SerializeField]
    public float OzoneAbsorptionScale = 1.0f;

    [SerializeField]
    public float OzoneLevelCenterHeight = 25000.0f;

    [SerializeField]
    public float OzoneLevelWidth = 15000.0f;

    [SerializeField]
    public float AerialPerspectiveDistance = 32000.0f;

    public RenderTargetIdentifier AtmosphericScatteringLut;
}
