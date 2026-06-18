// using UnityEngine;

// public class ServoBehave : MonoBehaviour
// {
//     [Range(0f, 360f)]
//     public float controlVal; // 0(inclusive) - 360(exclusive)

//     private float maxAngularSpeed = 600f; // do not change

//     private Transform childTf;

//     void Start()
//     {
//         if (transform.childCount > 0)
//             childTf = transform.GetChild(0);
//         else
//             Debug.LogWarning("[ServoBehave] No child object");
//     }

//     void FixedUpdate()
//     {
//         if (childTf == null) return;

//         float target = Mathf.Repeat(controlVal, 360f);

//         float current = childTf.localEulerAngles.y;

//         float delta = Mathf.DeltaAngle(current, target);

//         float maxStep = maxAngularSpeed * Time.fixedDeltaTime;

//         float newY;
//         if (Mathf.Abs(delta) >= 180)
//         {
//             Debug.Log("this should not happen");
//             Debug.Log(delta);
//         }
//         if (Mathf.Abs(delta) <= maxStep)
//         {
//             newY = target;
//         }
//         else
//         {
//             newY = current + Mathf.Sign(delta) * maxStep;
//         }

//         Vector3 e = childTf.localEulerAngles;
//         childTf.localEulerAngles = new Vector3(e.x, newY, e.z);
//     }
// }




using UnityEngine;

public class ServoBehave : MonoBehaviour
{
    [Range(0f, 360f)]
    public float controlVal; // 0(inclusive) - 360(exclusive)

    private float maxAngularSpeed = 600f; // do not change

    private Transform childTf;

    void Start()
    {
        if (transform.childCount > 0)
            childTf = transform.GetChild(0);
        else
            Debug.LogWarning("[ServoBehave] No child object");
    }

    void FixedUpdate()
    {
        if (childTf == null) return;

        float target = Mathf.Repeat(controlVal, 360f);

        float current = childTf.localEulerAngles.y;

        float delta = Mathf.DeltaAngle(current, target);

        float maxStep = maxAngularSpeed * Time.fixedDeltaTime;

        float newY;
        if (Mathf.Abs(delta) >= 180)
        {
            // Debug.Log("this should not happen");
        }
        
        if (Mathf.Abs(delta) <= maxStep)
        {
            newY = target;
        }
        else
        {
            newY = current + Mathf.Sign(delta) * maxStep;
        }

        Vector3 e = childTf.localEulerAngles;
        childTf.localEulerAngles = new Vector3(e.x, newY, e.z);
    }

    // [필수] 자식 오브젝트의 실제 회전 각도를 반환하는 함수
    public float GetCurrentAngle()
    {
        if (childTf != null)
            return childTf.localEulerAngles.y;
        
        return transform.localEulerAngles.y; 
    }
}



