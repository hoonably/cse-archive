using System.Collections.Generic;
using UnityEngine;

public class BrakeManager : MonoBehaviour
{
    [Header("Source of brakes")]
    public ControlUnit cu;
    public DroneControlUnit DCU;
    [Header("Target rigidbody (rocket)")]
    public Rigidbody rb;

    [Header("Global settings")]
    public float brakeConstant = 10;             
    private float stopSpeed = 0.1f;             
    private float safetyFactor = 0.95f;


    private readonly List<Vector3> _forces = new();
    private readonly List<Vector3> _positions = new();
    private ForceManager fm;
    private T GetComponentInParentsClosest<T>() where T : Component
    {
        Transform cur = transform;

        while (cur != null)
        {
            T comp = cur.GetComponent<T>();
            if (comp != null)
                return comp; // stop at the first (closest) match

            cur = cur.parent;
        }

        return null; // not found anywhere up the chain
    }

    void Start()
    {
        if (rb == null)
        {
            DCU = GetComponentInParentsClosest<DroneControlUnit>();
            if(DCU == null)
            {
                cu = GetComponentInParentsClosest<ControlUnit>();
                rb = cu.GetComponent<Rigidbody>();
            }
            else
            {
                rb = DCU.GetComponent<Rigidbody>();
            }
        }
        fm = GetComponent<ForceManager>();
    }

    void FixedUpdate()
    {
        _forces.Clear();
        _positions.Clear();

        if (cu!=null)
        {
            if (rb == null || cu.brake == null || cu.brake.Count == 0)
                return;


            foreach (var b in cu.brake)
            {
                if (b == null) continue;
                b.brakeConstant = brakeConstant;

                b.ComputeForce(rb, out var f, out var p);
                _forces.Add(f);
                _positions.Add(p);
                fm.AddForce(f, b.gameObject);

                b.UpdateVisuals();
            }
        }
        else 
        {
            if (rb == null || DCU.brake == null || DCU.brake.Count == 0)
                return;


            foreach (var b in DCU.brake)
            {
                if (b == null) continue;
                b.brakeConstant = brakeConstant;

                b.ComputeForce(rb, out var f, out var p);
                _forces.Add(f);
                _positions.Add(p);
                fm.AddForce(f, b.gameObject);

                b.UpdateVisuals();
            }
        }

        float dt = Time.fixedDeltaTime;

        Vector3 totalForce = Vector3.zero;
        for (int i = 0; i < _forces.Count; i++)
            totalForce += _forces[i];

        Vector3 v = rb.linearVelocity;
        float speed = v.magnitude;

        float k = 1f;
        if (speed > stopSpeed)
        {
            Vector3 vDir = v / speed;
            Vector3 J = totalForce * dt;

            float jParallel = Vector3.Dot(J, vDir);

            float maxAbsParallel = rb.mass * speed * safetyFactor;

            if (jParallel < -maxAbsParallel)
                k = (-maxAbsParallel) / jParallel;
        }
        else
        {
            k = 0.5f;
        }

        if (k < 1f)
        {
            for (int i = 0; i < _forces.Count; i++)
                _forces[i] *= k;
        }

        for (int i = 0; i < _forces.Count; i++)
        {
            rb.AddForceAtPosition(_forces[i], _positions[i], ForceMode.Force);
        }
    }
}
