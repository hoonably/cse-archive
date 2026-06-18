using UnityEngine;
using TMPro;
using System.Collections.Generic;

public class TimerBehave : MonoBehaviour
{
    public static TimerBehave Instance { get; private set; }

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

    public float panaltyForCollision;
    public float bonusForResource;
    public float timer;
    public float resourceCount;
    public bool inControl = false;
    public TMP_Text timer_text;
    public TMP_Text total_text;
    public TMP_Text total_resource;
    public CollisionDetector cd;
    public GlobalCollisionDetector gcd;
    private List<ResourceBehave> obtainedResources;

    bool isGCD;

    // Start is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {
        if (cd == null)
            isGCD = true;
        else
            isGCD = false;
        resourceCount = 0;
        obtainedResources = new List<ResourceBehave>();
    }

    public void leaveStartingPoint()
    {
        if(!inControl)
            inControl = true;
    }

    public void arriveFinishPoint()
    {
        inControl = false;
        if (isGCD)
        {
            gcd.isTriggering = false;
            total_text.text = (timer + gcd.collisionCount * panaltyForCollision - resourceCount * bonusForResource).ToString();
        }
        else
        {
            cd.isTriggering = false;
            total_text.text = (timer + cd.collisionCount * panaltyForCollision).ToString();
        }
    }

    public void getResource(ResourceBehave other)
    {
        if (obtainedResources.Contains(other))
            return;
        obtainedResources.Add(other);
        resourceCount++;
        total_resource.text = resourceCount.ToString();
    }

    // Update is called once per frame
    void Update()
    {
        if (inControl)
        {
            timer += Time.deltaTime;
            timer_text.text = timer.ToString("f2");
        }
    }
}
