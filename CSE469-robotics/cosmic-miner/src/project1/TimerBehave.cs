using UnityEngine;
using TMPro;
public class TimerBehave : MonoBehaviour
{
    public float panaltyForCollision;
    public float timer;
    public bool inControl = false;
    public TMP_Text timer_text;
    public TMP_Text total_text;
    public CollisionDetector cd;
    // Start is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {

    }

    public void leaveStartingPoint()
    {
        inControl = true;
    }

    public void arriveFinishPoint()
    {
        inControl = false;
        total_text.text = (timer + cd.collisionCount * panaltyForCollision).ToString();
        cd.isTriggering = false;
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
