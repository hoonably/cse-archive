using UnityEngine;

public class ThrusterBehave : MonoBehaviour
{
    [Header("Input")]
    [Tooltip("0~1 비율 입력")]
    public float controlVal; // 0 ~ 1

    [Header("Thrust")]
    [Tooltip("Inspector에서 값을 입력하면 자동으로 5~60으로 클램핑되고, 크기(scale)는 (maxThrust/10)^(1/3)로 맞춰집니다.")]
    public float maxThrust = 10f; // Inspector에서 조정

    [Header("Internal (do not change)")]
    [SerializeField, Tooltip("Dead zone for visuals only")]
    private float deadZone = 0.1f; // do not change
    private Rigidbody rb;
    private ParticleSystem ps;
    [SerializeField] private float maxEmit = 100f; // do not change

    void Start()
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
        ps = GetComponentInChildren<ParticleSystem>();

        // 런타임 진입 시에도 한번 더 보정
        ClampThrustAndApplyScale();
    }

    void FixedUpdate()
    {
        controlVal = Mathf.Clamp01(controlVal);

        Vector3 worldDir = transform.TransformDirection(Vector3.right);
        rb.AddForceAtPosition(worldDir * maxThrust * controlVal, transform.position, ForceMode.Force);

        Visuals();
    }

    void Visuals()
    {
        if (ps == null) return;
        var emission = ps.emission;
        emission.rateOverTime = (controlVal < deadZone) ? 0f : maxEmit * controlVal;
    }

#if UNITY_EDITOR
    // Inspector에서 값이 바뀔 때마다 호출 (Play/Editor 둘 다)
    void OnValidate()
    {
        ClampThrustAndApplyScale();
    }
#endif

    void ClampThrustAndApplyScale()
    {
        // 1) 5~60으로 자동 클램핑
        maxThrust = Mathf.Clamp(maxThrust, 0f, 60f);

        // 2) 스케일 = (maxThrust / 10)^(1/3)
        //    10을 기준으로 10일 때 스케일 1, 80이면 2가 되도록(부피 ~ 추력 비례 가정 시 자연스러운 큐브루트 스케일링)
        float s = Mathf.Pow(maxThrust / 10f, 1f / 3f);
        transform.localScale = new Vector3(s, s, s);
        var temp = ps.main;
        temp.startSize = s;
        temp.startSpeed = s * -10f;
    }
}
