using UnityEngine;

public class LocalCollisionDetector : MonoBehaviour
{
    private GlobalCollisionDetector gcd;
    // Start is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {
        gcd = GlobalCollisionDetector.Instance;
    }

    void OnCollisionStay(Collision collision)
    {
        if (Time.time < gcd._nextAllowedTime) return;

        GameObject other = collision.gameObject;

        if (other.CompareTag("Player"))
        {
            gcd.AddCount();
            return;
        }
    }
}
