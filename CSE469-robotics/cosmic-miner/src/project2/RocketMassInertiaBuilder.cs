using System.Collections.Generic;
using UnityEngine;

[DisallowMultipleComponent]
public class RocketMassInertiaBuilder : MonoBehaviour
{
    [Header("References")]
    public Rigidbody rb;

    [Header("Body/Brake Base Settings")]
    public bool sphereBody = false;
    public float bodyMass = 10f;
    public float bodyLength = 2f;
    public float brakeMass = 0.1f;
    public float brakeLength = 1f;

    [Header("Thruster Mass Rule")]
    public float thrustMassDivisor = 10f; // mass scaling rule for thrusters

    [Header("Axis Control")]
    public bool exaggerateIxIz = true;
    public float lockMultiplier = 1000f;

    // Cached per-part data that does not change at runtime
    private struct PartInfo
    {
        public Transform tf;        // transform of this part
        public float mass;          // mass of this part
        public float IyIntrinsic;   // intrinsic moment of inertia about local Y axis of the part's own COM
    }

    // All parts of the rocket (body, thrusters, brakes)
    private List<PartInfo> parts = new List<PartInfo>();

    // Total mass of the whole rocket (constant since mass does not change)
    private float totalMassCached;

    void Reset()
    {
        rb = GetComponent<Rigidbody>();
    }

    void Start()
    {
        if (rb == null) rb = GetComponent<Rigidbody>();

        // Build the static part list and cache all invariant properties
        BuildStaticPartList();

        // Do one initial update to apply COM and inertia to the rigidbody
        UpdateMassProps();
    }

    void FixedUpdate()
    {
        // Update only position-dependent properties (center of mass and Iy)
        UpdateMassProps();
    }

    // Gathers all parts (body, thrusters, brakes) and caches:
    // - mass
    // - Iy intrinsic
    // - transform reference
    // This only needs to run once because parts do not get created/destroyed
    private void BuildStaticPartList()
    {
        parts.Clear();
        totalMassCached = 0f;

        // 1. Main body
        {
            float m = Mathf.Max(0f, bodyMass);

            // Treat body as a uniform rod aligned with its local Y axis of length bodyLength
            // Iy of a rod around its center for rotation around Y is (1/12) * m * L^2
            float Iy_intrinsic = (1f / 12f) * m * (bodyLength * bodyLength);
            if (sphereBody)
            {
                Iy_intrinsic = (2f / 5f) * m * (bodyLength * bodyLength);
            }

            parts.Add(new PartInfo
            {
                tf = this.transform, // assume body COM is at rocket root for modeling
                mass = m,
                IyIntrinsic = Iy_intrinsic
            });

            totalMassCached += m;
        }

        // 2. Thrusters
        var thrusters = GetComponentsInChildren<ThrusterBehave>(includeInactive: true);
        foreach (var t in thrusters)
        {
            if (t == null) continue;

            float T = Mathf.Max(0f, t.maxThrust);
            float mt = T / thrustMassDivisor;

            // Approximate thruster as a solid cylinder
            // We derive size s from thrust for visual mass scaling
            float s = Mathf.Pow(T / 10f, 1f / 3f);

            float r = 0.25f * s; // radius
            float h = 1.0f * s;  // height

            // Moment of inertia of a solid cylinder about its own central Y axis:
            // Iy = (1/12)*m*(3r^2 + h^2)
            float Iy_intrinsic = (1f / 12f) * mt * (3f * r * r + h * h);

            parts.Add(new PartInfo
            {
                tf = t.transform,
                mass = mt,
                IyIntrinsic = Iy_intrinsic
            });

            totalMassCached += mt;
        }

        // 3. Brakes
        var brakes = GetComponentsInChildren<BrakeBehave>(includeInactive: true);
        foreach (var b in brakes)
        {
            if (b == null) continue;

            float mr = Mathf.Max(0f, brakeMass);

            // Treat brake like a uniform rod of length brakeLength
            float Iy_intrinsic = (1f / 12f) * mr * (brakeLength * brakeLength);

            parts.Add(new PartInfo
            {
                tf = b.transform,
                mass = mr,
                IyIntrinsic = Iy_intrinsic
            });

            totalMassCached += mr;
        }
    }

    // Recomputes runtime-dependent properties:
    // - Center of mass in local coordinates
    // - Iy about that COM using parallel axis theorem
    // Then applies those values to the Rigidbody
    private void UpdateMassProps()
    {
        if (rb == null) return;
        if (parts.Count == 0) return;
        if (totalMassCached <= 0f) return;

        // 1. Compute center of mass in rocket local space
        Vector3 weightedSum = Vector3.zero;
        for (int i = 0; i < parts.Count; i++)
        {
            PartInfo p = parts[i];
            Vector3 localPos = transform.InverseTransformPoint(p.tf.position);
            weightedSum += p.mass * localPos;
        }

        Vector3 comLocal = weightedSum / totalMassCached;

        // 2. Compute Iy about that COM using parallel axis theorem
        // Iy_total = sum( Iy_intrinsic_i + m_i * d^2 ), where d is distance in XZ plane
        double Iy = 0.0;
        for (int i = 0; i < parts.Count; i++)
        {
            PartInfo p = parts[i];
            Vector3 localPos = transform.InverseTransformPoint(p.tf.position);

            float dx = localPos.x - comLocal.x;
            float dz = localPos.z - comLocal.z;
            double d2 = (double)dx * dx + (double)dz * dz;

            Iy += p.IyIntrinsic + p.mass * d2;
        }

        // 3. Apply to Rigidbody
        rb.mass = totalMassCached;
        rb.centerOfMass = comLocal;

        float Iy_f = (float)Iy;

        // Ix and Iz can be artificially locked by inflating them.
        // This is a gameplay/controls trick to resist rolling/pitching etc.
        float Ix = exaggerateIxIz ? Mathf.Max(1f, Iy_f * lockMultiplier) : Iy_f;
        float Iz = exaggerateIxIz ? Mathf.Max(1f, Iy_f * lockMultiplier) : Iy_f;

        // We assume principal axes are aligned with the rocket's local axes
        rb.inertiaTensorRotation = Quaternion.identity;
        rb.inertiaTensor = new Vector3(Ix, Iy_f, Iz);
    }
}
