using UnityEngine;
using System.Collections.Generic;

public class GPS_Behave : MonoBehaviour
{
    [Header("Ordered checkpoints to visit")]
    public List<checkpointBehave> checkpoints = new List<checkpointBehave>();
    public List<checkpointBehave> pivots = new List<checkpointBehave>();
    public List<checkpointBehave> ends = new List<checkpointBehave>();

    public Vector3 currentPos;

    private void Start()
    {
        currentPos = this.transform.position;
    }

    // Update is called once per frame
    void Update()
    {
        currentPos = this.transform.position;
    }
}
