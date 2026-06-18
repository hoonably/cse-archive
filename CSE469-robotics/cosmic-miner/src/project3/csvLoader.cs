using System.Collections.Generic;
using System.IO;
using UnityEngine;

public class csvLoader : MonoBehaviour
{
    [Header("CSV file name")]
    public string csvFileName;

    [Header("Loaded trajectory data (time,x,z)")]
    public List<Vector3> loadedData = new List<Vector3>();

    void Start()
    {
        string dir = Application.dataPath;
        string fullPath = Path.Combine(dir, csvFileName);

        if (!File.Exists(fullPath))
        {
            Debug.LogError("File not found: " + fullPath);
            return;
        }

        string[] lines = File.ReadAllLines(fullPath);
        loadedData.Clear();

        // skip first line (Header)
        for (int i = 1; i < lines.Length; i++)
        {
            string line = lines[i].Trim();
            if (string.IsNullOrEmpty(line)) continue;

            string[] tokens = line.Split(',');
            if (tokens.Length < 3) continue;

            float t = float.Parse(tokens[0]);
            float x = float.Parse(tokens[1]);
            float z = float.Parse(tokens[2]);

            loadedData.Add(new Vector3(t, x, z));
        }

        Debug.Log("csv file Loaded " + loadedData.Count + " datas from " + csvFileName);
    }
}
