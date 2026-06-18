using System.Collections.Generic;
using UnityEngine;

public class BrakeManager : MonoBehaviour
{
    [Header("Source of brakes")]
    public ControlUnit cu;                        // cu.brake: List<BrakeBehave>
    [Header("Target rigidbody (rocket)")]
    public Rigidbody rb;

    [Header("Global settings")]
    public float brakeConstant = 10;             // 전 브레이크 공통 C (개별 조정하려면 각 BrakeBehave에 세팅)
    private float stopSpeed = 0.1f;              // 이 이하 속도면 실질적 정지로 간주(과도한 떨림 방지)
    private float safetyFactor = 0.95f;  // <= mv의 몇 %까지만 감속 허용할지

    // 내부 캐시
    private readonly List<Vector3> _forces = new();
    private readonly List<Vector3> _positions = new();

    void Reset()
    {
        // 태그/구조가 정해져 있다면 자동으로 찾아도 됨
        if (rb == null)
        {
            GameObject[] parts = GameObject.FindGameObjectsWithTag("Player");
            foreach (GameObject part in parts)
            {
                if (part.GetComponent<ControlUnit>())
                {
                    rb = part.GetComponent<Rigidbody>();
                    break;
                }
            }
        }
    }

    void FixedUpdate()
    {
        if (rb == null || cu == null || cu.brake == null || cu.brake.Count == 0)
            return;

        _forces.Clear();
        _positions.Clear();

        // 각 브레이크의 제안 힘 계산
        foreach (var b in cu.brake)
        {
            if (b == null) continue;
            b.brakeConstant = brakeConstant;

            b.ComputeForce(rb, out var f, out var p);
            _forces.Add(f);
            _positions.Add(p);

            b.UpdateVisuals();
        }

        // 총 임펄스 기반 클램프 (속도 방향 성분만 제한)
        float dt = Time.fixedDeltaTime;

        Vector3 totalForce = Vector3.zero;
        for (int i = 0; i < _forces.Count; i++)
            totalForce += _forces[i];

        Vector3 v = rb.linearVelocity;
        float speed = v.magnitude;

        float k = 1f; // 스케일 팩터(<=1)
        if (speed > stopSpeed)
        {
            Vector3 vDir = v / speed;
            // 총 임펄스 J = F * dt
            Vector3 J = totalForce * dt;

            // 속도 방향 성분(스칼라). 보통 drag라 음수일 것.
            float jParallel = Vector3.Dot(J, vDir);

            // 오버슛 방지 조건: |jParallel| > m*|v|
            float maxAbsParallel = rb.mass * speed * safetyFactor;

            // jParallel이 -maxAbsParallel보다 더 작아지면(=너무 큰 감속) 스케일 필요
            if (jParallel < -maxAbsParallel)
                k = (-maxAbsParallel) / jParallel; // jParallel<0이므로 0<k<1
        }
        else
        {
            // 사실상 정지 상태: 필요시 작은 감쇠만 허용하거나 완전 차단
            // 여기서는 과감히 속도 방향 감쇠는 차단하고, 측면(방향 전환) 성분만 적용하고 싶다면
            // k를 1로 두고 아래에서 방향 분해 적용하는 로직을 추가해도 됨.
            // 간단히 전부 약하게:
            k = 0.5f; // or 0f to fully stop applying when near zero
        }

        // 동일 비율로 모든 힘을 스케일 후, 해당 지점에 적용 → 토크도 동일 비율로 자연스레 스케일
        if (k < 1f)
        {
            for (int i = 0; i < _forces.Count; i++)
                _forces[i] *= k;
        }

        for (int i = 0; i < _forces.Count; i++)
        {
            rb.AddForceAtPosition(_forces[i] * Time.fixedDeltaTime, _positions[i], ForceMode.Impulse);
            //Debug.Log(_forces[i].magnitude + ", " + _positions[i].x + ", " + _positions[i].z);
            //Debug.Log(rb.linearVelocity.x + ", " + rb.linearVelocity.z);
        }
    }
}
