using UnityEngine;
using System.Collections.Generic;
public class ForceManager : MonoBehaviour
{
    public List<Vector3> forceList;
    public List<GameObject> forceTargetList;
    private Rigidbody rb;

    public Vector3 sumForce;
    public Vector3 sumTorque;

    // Start is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {
        rb = GetComponent<Rigidbody>();
    }

    // Update is called once per frame
    public void AddForce(Vector3 force, GameObject target)
    {
        if (forceTargetList.Contains(target))
        {
            int i = forceTargetList.IndexOf(target);
            forceList[i] = force;
        }
        else
        {
            forceList.Add(force);
            forceTargetList.Add(target);
        }
    }

    public void FixedUpdate()
    {
        if(forceList.Count > 0)
        {
            sumForce = Vector3.zero;
            sumTorque = Vector3.zero;
            for (int i=0;i<forceList.Count;i++)
            {
                sumForce += forceList[i];
                if (forceTargetList[i] == rb.gameObject)
                {
                    continue;
                }
                else
                {
                    Vector3 r = forceTargetList[i].transform.position - rb.worldCenterOfMass;
                    sumTorque += Vector3.Cross(r, forceList[i]);
                }
            }
        }

        forceList.Clear();
        forceTargetList.Clear();
    }
}
