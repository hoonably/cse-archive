using System.Collections.Generic;
using System.IO;
using UnityEngine;

public class TrajectoryRecorder : MonoBehaviour
{
    [Header("Recording target (object to track)")]
    public Transform target;

    [Header("Recording state (read-only in play)")]
    public bool isRecording = false;

    // Internal list to store (time, x, z)
    private List<Vector3> recordedData = new List<Vector3>();

    private bool pendingSave = false;
    private float startTime = 0f;

    void Update()
    {
        // Toggle recording with Space
        if (Input.GetKeyDown(KeyCode.Space))
        {
            if (!isRecording)
            {
                // Start recording
                isRecording = true;
                recordedData.Clear();
                pendingSave = false;
                startTime = Time.time;  // reference time = now
                Debug.Log("[TrajectoryRecorder] Recording START (t=0)");
            }
            else
            {
                // Stop recording
                isRecording = false;
                pendingSave = true;
                Debug.Log("[TrajectoryRecorder] Recording STOP");
            }
        }

        // Save once when recording stops
        if (pendingSave && !isRecording)
        {
            SaveCsv();
            pendingSave = false;
        }
    }

    void FixedUpdate()
    {
        if (isRecording && target != null)
        {
            Vector3 p = target.position;
            float elapsed = Time.time - startTime;
            // Store (time, x, z)
            recordedData.Add(new Vector3(elapsed, p.x, p.z));
        }
    }

    private void SaveCsv()
    {
        if (recordedData.Count == 0)
        {
            Debug.LogWarning("[TrajectoryRecorder] Nothing to save (no samples).");
            return;
        }

        System.Text.StringBuilder sb = new System.Text.StringBuilder();
        sb.AppendLine("time_sec,x,z");

        foreach (var v in recordedData)
        {
            sb.Append(v.x.ToString("F6")).Append(","); // time
            sb.Append(v.y.ToString("F6")).Append(","); // x
            sb.Append(v.z.ToString("F6")).AppendLine(); // z
        }

        string timeStamp = System.DateTime.Now.ToString("yyyyMMdd_HHmmss_fff");
        string fileName = "trajectory_" + timeStamp + ".csv";
        string dir = Application.dataPath;
        string fullPath = Path.Combine(dir, fileName);

        try
        {
            File.WriteAllText(fullPath, sb.ToString());
            Debug.Log("[TrajectoryRecorder] Saved CSV: " + fullPath);
        }
        catch (System.Exception e)
        {
            Debug.LogError("[TrajectoryRecorder] Failed to save CSV:\n" + e);
        }
    }
}
