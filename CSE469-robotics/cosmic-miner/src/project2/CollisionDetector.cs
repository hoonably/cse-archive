using UnityEngine;
using TMPro;

public class CollisionDetector : MonoBehaviour
{
    public bool isTriggering = true;
    public TMP_Text collisionCountText;
    public float thresholdTime;

    public int collisionCount;

    float _nextAllowedTime = 0f;

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
}
