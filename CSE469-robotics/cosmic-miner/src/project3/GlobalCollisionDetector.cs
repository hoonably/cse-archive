using UnityEngine;
using TMPro;

public class GlobalCollisionDetector : MonoBehaviour
{
    public static GlobalCollisionDetector Instance { get; private set; }

    private void Awake()
    {
        // 이미 인스턴스가 존재하는데 새로 생기려 하면 파괴
        if (Instance != null && Instance != this)
        {
            Destroy(gameObject);
            return;
        }

        Instance = this;
    }


    public bool isTriggering = true;
    public TMP_Text collisionCountText;
    public float thresholdTime = 5f;

    public int collisionCount;

    public float _nextAllowedTime = 0f;

    // Start is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {
        collisionCount = 0;
    }

    // Update is called once per frame
    void Update()
    {
        
    }

    public void AddCount()
    {
        if (isTriggering)
        {
            collisionCount++;
            _nextAllowedTime = Time.time + thresholdTime;
            collisionCountText.text = collisionCount.ToString();
        }
    }
}
