using UnityEngine;
using TMPro;

public class CollisionDetector : MonoBehaviour
{
    public bool isTriggering = true;
    public TMP_Text collisionCountText;
    public float thresholdTime;

    public int collisionCount;

    float _nextAllowedTime = 0f;
    
    // ControlUnit 참조 (Inspector에서 할당)
    private ControlUnit controlUnit;
    
    void Start()
    {
        controlUnit = GetComponentInParent<ControlUnit>();
        if (controlUnit == null)
        {
            controlUnit = FindFirstObjectByType<ControlUnit>();
        }
    }

    void OnCollisionStay(Collision collision)
    {
        if (Time.time < _nextAllowedTime) return;

        GameObject other = collision.gameObject;

        if (other.CompareTag("Player"))
        {
            CountAndCooldown();
            return;
        }

        var fj = other.GetComponent<FixedJoint>();
        if (fj != null)
        {
            var connected = fj.connectedBody;
            if (connected != null && connected.gameObject.CompareTag("Player"))
            {
                CountAndCooldown();
                return;
            }
        }

    }

    void CountAndCooldown()
    {
        if (isTriggering)
        {
            collisionCount++;
            _nextAllowedTime = Time.time + thresholdTime;
            collisionCountText.text = collisionCount.ToString();
        }
    }
    
    void OnCollisionEnter(Collision collision)
    {
        LogCollisionInfo(collision, "ENTER");
    }
    
    private void LogCollisionInfo(Collision collision, string eventType)
    {
        if (controlUnit == null) return;
        
        var GPS = controlUnit.GPS;
        var IMU = controlUnit.IMU;
        var servo = controlUnit.servo;
        var brake = controlUnit.brake;
        var engine = controlUnit.engine;
        
        if (GPS == null || GPS.Count == 0 || IMU == null || IMU.Count == 0 || servo == null || servo.Count == 0)
            return;
        
        Vector3 currentPos = GPS[0].currentPos;
        Vector3 localVel = controlUnit.transform.InverseTransformDirection(IMU[0].linearVelocity);
        Vector3 worldVel = IMU[0].linearVelocity;
        Vector3 localAccel = controlUnit.transform.InverseTransformDirection(IMU[0].accel);
        float lateralDrift = localVel.x + localAccel.x * 0.4f;
        float driftComp = Mathf.Clamp(-lateralDrift * 3f, -15f, 15f);
        
        string brakeInfo = brake.Count >= 5 ? 
            $"L={brake[0].controlVal:F2} R={brake[1].controlVal:F2} FB={brake[4].controlVal:F2}" : 
            "N/A";
        
        float thrust = engine.Count > 0 ? engine[0].controlVal : 0f;
        
        int gridX = Mathf.RoundToInt(currentPos.x / 12.0f) + 10;
        int gridZ = Mathf.RoundToInt(currentPos.z / 12.0f) + 10;
        string currentGrid = $"({gridX},{gridZ})";
        
        int targetGridX = Mathf.RoundToInt(controlUnit.autoTargetPos.x / 12.0f) + 10;
        int targetGridZ = Mathf.RoundToInt(controlUnit.autoTargetPos.z / 12.0f) + 10;
        string targetGrid = $"({targetGridX},{targetGridZ})";
        
        Debug.Log(
            $"<color=red>[COLLINFO-{eventType}]</color> ========== COLLISION DETECTED ==========\n" +
            $"Position: {currentGrid} World=({currentPos.x:F1}, {currentPos.z:F1}) | Target: {targetGrid} ({controlUnit.autoTargetPos.x:F1}, {controlUnit.autoTargetPos.z:F1})\n" +
            $"Velocity: Local=({localVel.x:F2}, {localVel.z:F2}) World=({worldVel.x:F2}, {worldVel.z:F2}) | LateralDrift={lateralDrift:F2}\n" +
            $"Servo: Current={servo[0].controlVal:F1}° Target={controlUnit.targetEngineAngle:F1}° | AngleError={Mathf.DeltaAngle(servo[0].controlVal, controlUnit.targetEngineAngle):F1}° | DriftComp={driftComp:F1}°\n" +
            $"Control: Thrust={thrust:F2} Brake=[{brakeInfo}] Mode={controlUnit.currentMode}\n" +
            $"Collision: Object={collision.gameObject.name} Tag={collision.gameObject.tag} Point=({collision.contacts[0].point.x:F1}, {collision.contacts[0].point.z:F1}) Normal=({collision.contacts[0].normal.x:F2}, {collision.contacts[0].normal.z:F2})"
        );
    }
}
