using UnityEngine;

public class BrakeBehave : MonoBehaviour
{
    [Range(0f, 1f)] public float controlVal; // 0 ~ 1
    [HideInInspector] public float brakeConstant;
    [HideInInspector] private float brakeAngle = 90f;

    private GameObject brakeUp;
    private GameObject brakeDown;
    private Quaternion upInitLocalRot;
    private Quaternion downInitLocalRot;

    void Awake()
    {
        brakeUp = transform.GetChild(1).gameObject;
        brakeDown = transform.GetChild(0).gameObject;
        upInitLocalRot = brakeUp.transform.localRotation;
        downInitLocalRot = brakeDown.transform.localRotation;
    }

    /// <summary>
    /// 현재 Rigidbody 상태에서 이 브레이크가 제안하는 힘(로컬 X, Y 성분 drag)을 계산.
    /// 실제 적용은 매니저에서 일괄 수행한다.
    /// </summary>
    public void ComputeForce(Rigidbody rb, out Vector3 force, out Vector3 atPos)
    {
        controlVal = Mathf.Clamp01(controlVal);

        atPos = transform.position;

        // 이 지점에서의 속도(선속도 + 회전에 의한 접선속도 포함)
        Vector3 v = rb.GetPointVelocity(atPos);

        // 브레이크 로컬 축
        Vector3 axisX = transform.right;  // 제어형 드래그
        Vector3 axisY = transform.up;     // 항상 최대 드래그

        float vX = Vector3.Dot(v, axisX);
        float vY = Vector3.Dot(v, axisY);

        // 제곱형 저항: F = -C * v * |v| * axis
        Vector3 Fx = -brakeConstant * vX * Mathf.Abs(vX) * axisX * controlVal;
        Vector3 Fy = -brakeConstant * vY * Mathf.Abs(vY) * axisY;

        force = Fx + Fy;
    }

    /// <summary> 플랩 비주얼(원하면 매니저에서 매 프레임 호출) </summary>
    public void UpdateVisuals()
    {
        float ang = brakeAngle * controlVal;
        brakeUp.transform.localRotation = upInitLocalRot * Quaternion.AngleAxis(ang, Vector3.forward);
        brakeDown.transform.localRotation = downInitLocalRot * Quaternion.AngleAxis(-ang, Vector3.forward);
    }
}
