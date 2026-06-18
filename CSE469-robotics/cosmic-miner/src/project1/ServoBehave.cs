using UnityEngine;

public class ServoBehave : MonoBehaviour
{
    [Tooltip("목표 각도(0 이상 360 미만, degrees)")]
    [Range(0f, 360f)]
    public float controlVal; // 0(inclusive) - 360(exclusive)

    private float maxAngularSpeed = 600f; // do not change

    private Transform childTf;

    void Start()
    {
        // 첫 번째 자식을 사용 (필요시 직접 할당하도록 바꿔도 됨)
        if (transform.childCount > 0)
            childTf = transform.GetChild(0);
        else
            Debug.LogWarning("[ServoBehave] 자식이 없습니다. 회전 대상이 필요합니다.");
    }

    void FixedUpdate()
    {
        if (childTf == null) return;

        // 목표 각도는 0~360 범위로 래핑
        float target = Mathf.Repeat(controlVal, 360f);

        // 현재 로컬 Z 각도(0~360)
        float current = childTf.localEulerAngles.y;

        // 최단 경로 기준 각도 차이(-180 ~ +180)
        float delta = Mathf.DeltaAngle(current, target);

        // 이번 프레임에 허용되는 최대 회전량
        float maxStep = maxAngularSpeed * Time.fixedDeltaTime;

        float newY;
        if (Mathf.Abs(delta) <= maxStep)
        {
            // 목표에 충분히 가까우면 스냅
            newY = target;
        }
        else
        {
            // 최단 방향으로 maxStep만큼 회전
            newY = current + Mathf.Sign(delta) * maxStep;
        }

        // X/Y는 유지하고 Z만 갱신
        Vector3 e = childTf.localEulerAngles;
        childTf.localEulerAngles = new Vector3(e.x, newY, e.z);
    }
}
