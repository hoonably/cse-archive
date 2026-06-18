using UnityEngine;
using TMPro;

public class CollisionDetector : MonoBehaviour
{
    public bool isTriggering = true;
    public TMP_Text collisionCountText;
    [Tooltip("충돌 1회 집계 후, 이 시간(초) 동안은 추가 집계를 막습니다.")]
    public float thresholdTime;

    [Tooltip("집계된 충돌 횟수")]
    public int collisionCount;

    // 다음 집계가 허용되는 시각(Time.time 기준)
    float _nextAllowedTime = 0f;

    void OnCollisionStay(Collision collision)
    {
        // 쿨다운 중이면 아무 것도 집계하지 않음
        if (Time.time < _nextAllowedTime) return;

        GameObject other = collision.gameObject;

        // 1) 충돌체가 Player 태그
        if (other.CompareTag("Player"))
        {
            CountAndCooldown();
            return;
        }

        // 2) 충돌체가 FixedJoint를 가지고 있고, 그 연결 대상이 Player
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
            // Debug.Log($"Collision counted: {collisionCount}");
        }
    }
}
