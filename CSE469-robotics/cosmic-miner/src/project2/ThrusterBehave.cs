using UnityEngine;

public class ThrusterBehave : MonoBehaviour
{
    [Header("Input")]
    [Range(0f, 1f)] public float controlVal; // 0 ~ 1

    [Header("Thrust")]
    public float maxThrust = 10f; 

    [Header("Internal (do not change)")]
    [SerializeField, Tooltip("Dead zone for visuals only")]
    private float deadZone = 0.1f; // do not change
    private Rigidbody rb;
    private ParticleSystem ps;
    [SerializeField] private float maxEmit = 500f; // do not change
    private AudioSource sor;

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
            DroneControlUnit DCU = GetComponentInParentsClosest<DroneControlUnit>();
            if(DCU == null)
            {
                ControlUnit cu = GetComponentInParentsClosest<ControlUnit>();
                rb = cu.GetComponent<Rigidbody>();
            }
            else
            {
                rb = DCU.GetComponent<Rigidbody>();
            }
        }
        ps = GetComponentInChildren<ParticleSystem>();

        ClampThrustAndApplyScale();
        sor = this.GetComponent<AudioSource>();
        sor.pitch = (maxThrust / 30) * 2f - 3f;
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

        if(sor != null)
        {
            sor.volume = maxThrust > 10f ? controlVal : controlVal * maxThrust / 10f;
        }
    }

#if UNITY_EDITOR
    void OnValidate()
    {
        ClampThrustAndApplyScale();
    }
#endif

    void ClampThrustAndApplyScale()
    {
        maxThrust = Mathf.Clamp(maxThrust, 0f, 60f);

        float s = Mathf.Pow(maxThrust / 10f, 1f / 3f);
        transform.localScale = new Vector3(s, s, s);
        ps = GetComponentInChildren<ParticleSystem>();
        var temp = ps.main;
        temp.startSize = s;
        temp.startSpeed = s * -10f;
    }
}
