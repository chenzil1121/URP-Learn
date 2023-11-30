using System.Collections;
using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;

[CustomEditor(typeof(CloudNoiseGenerator))]
public class CloudNoiseGenEditor : Editor
{
    CloudNoiseGenerator noise;
    Editor noiseSettingsEditor;

    public override void OnInspectorGUI()
    {
        DrawDefaultInspector();

        if (GUILayout.Button("Save"))
        {
            Save();
        }
    }

    void Save()
    {
        noise.UpdateNoise();
    }

    void OnEnable()
    {
        noise = (CloudNoiseGenerator)target;
    }
}
