using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// 로켓 동체의 질량, 질량중심(CoM), 전역 y축 관성모멘트(Iy)를
/// 자식 Thruster/Brake 구성에 따라 Start에서 동적으로 계산해 Rigidbody에 반영.
/// </summary>
[DisallowMultipleComponent]
public class RocketMassInertiaBuilder : MonoBehaviour
{
    [Header("References")]
    public Rigidbody rb; // 미지정 시 자동 GetComponent

    [Header("Body/Brake Base Settings")]
    [Tooltip("동체(Body) 고정 질량 [kg]")]
    public float bodyMass = 10f;
    [Tooltip("동체 막대 길이 [m] (y축에 수직)")]
    public float bodyLength = 2f;
    [Tooltip("에어브레이크 1개당 질량 [kg]")]
    public float brakeMass = 0.1f;
    [Tooltip("에어브레이크 막대 길이 [m] (y축에 수직)")]
    public float brakeLength = 1f;

    [Header("Thruster Mass Rule")]
    [Tooltip("Thruster 질량 산정: m_t = maxThrust / thrustMassDivisor")]
    public float thrustMassDivisor = 10f; // 문제 정의: m = MaxThrust/10

    [Header("Axis Control")]
    [Tooltip("y축만 회전하도록 X/Z는 관성 크게 설정")]
    public bool exaggerateIxIz = true;
    [Tooltip("Ix, Iz = Iy * lockMultiplier (yaw만 허용 효과)")]
    public float lockMultiplier = 1000f;

    // 내부 캐시
    private List<(float m, Vector3 localPos, float Iy_intrinsic)> _parts = new();

    void Reset()
    {
        rb = GetComponent<Rigidbody>();
    }

    void Start()
    {
        if (rb == null) rb = GetComponent<Rigidbody>();
        Rebuild();
    }

    /// <summary>
    /// 수동 재계산이 필요할 때 호출(에디터 버튼 등에서 호출 가능)
    /// </summary>
    [ContextMenu("Rebuild Mass/CoM/Iy")]
    public void Rebuild()
    {
        _parts.Clear();
        if (rb == null) { Debug.LogError("[RocketMassInertiaBuilder] Rigidbody not set."); return; }

        // === 1) 자식 수집 및 질량/자체 Iy 계산 ===
        float totalMass = 0f;

        // 1-1) Body 자신 (원점, 길이 bodyLength, y축 수직)
        {
            float m = Mathf.Max(0f, bodyMass);
            Vector3 localPos = Vector3.zero; // 동체의 기준점이 CoM이라 가정
            float Iy_intrinsic = (1f / 12f) * m * (bodyLength * bodyLength); // 막대, 축 수직 y
            _parts.Add((m, localPos, Iy_intrinsic));
            totalMass += m;
        }

        // 1-2) Thruster들
        var thrusters = GetComponentsInChildren<ThrusterBehave>(includeInactive: true);
        foreach (var t in thrusters)
        {
            if (t == null) continue;
            float T = Mathf.Max(0f, t.maxThrust);
            float mt = T / thrustMassDivisor;

            // 스케일 s = (T/10)^(1/3)  (분모 10은 문제 정의 고정)
            float s = Mathf.Pow(T / 10f, 1f / 3f);

            // 원기둥 치수 (기준 d0=0.5, h0=1.0) → d=0.5*s, r=0.25*s, h=1*s
            float r = 0.25f * s;
            float h = 1.0f * s;

            // 자체 Iy (원기둥, 축 수직 y): Iy = (1/12) m (3 r^2 + h^2)
            float Iy_intrinsic = (1f / 12f) * mt * (3f * r * r + h * h);

            Vector3 localPos = transform.InverseTransformPoint(t.transform.position);
            _parts.Add((mt, localPos, Iy_intrinsic));
            totalMass += mt;
        }

        // 1-3) Brakes
        var brakes = GetComponentsInChildren<BrakeBehave>(includeInactive: true);
        foreach (var b in brakes)
        {
            if (b == null) continue;
            float mr = Mathf.Max(0f, brakeMass);
            float Iy_intrinsic = (1f / 12f) * mr * (brakeLength * brakeLength); // 막대, 축 수직 y
            Vector3 localPos = transform.InverseTransformPoint(b.transform.position);
            _parts.Add((mr, localPos, Iy_intrinsic));
            totalMass += mr;
        }

        // === 2) 질량중심(CoM) (Body 로컬 기준) ===
        Vector3 comLocal = Vector3.zero;
        if (totalMass > 0f)
        {
            Vector3 sum = Vector3.zero;
            foreach (var p in _parts)
                sum += p.m * p.localPos;
            comLocal = sum / totalMass;
        }

        // === 3) 전역 y축 관성모멘트 Iy 합산 (병진축 정리) ===
        // d_perp^2 = (x - x_c)^2 + (z - z_c)^2  (y축 수직거리)
        double Iy = 0.0;
        foreach (var p in _parts)
        {
            float dx = p.localPos.x - comLocal.x;
            float dz = p.localPos.z - comLocal.z;
            double d2 = (double)dx * dx + (double)dz * dz;
            Iy += p.Iy_intrinsic + p.m * d2;
        }

        // === 4) Rigidbody에 반영 ===
        rb.mass = totalMass;
        rb.centerOfMass = comLocal;

        // inertiaTensor는 로컬 축 기준. 여기서는 y축이 로컬 y라고 가정.
        // y축만 회전 허용하려면 Ix/Iz를 크게 설정(또는 Constraints로 X/Z 회전 고정해도 됨).
        float Iy_f = (float)Iy;
        float Ix = exaggerateIxIz ? Mathf.Max(1f, Iy_f * lockMultiplier) : Iy_f;
        float Iz = exaggerateIxIz ? Mathf.Max(1f, Iy_f * lockMultiplier) : Iy_f;

        rb.inertiaTensorRotation = Quaternion.identity; // 로컬 축 정렬 가정
        rb.inertiaTensor = new Vector3(Ix, Iy_f, Iz);
    }
}
