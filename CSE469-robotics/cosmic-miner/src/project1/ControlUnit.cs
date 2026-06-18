using UnityEngine;
using UnityEngine.InputSystem;
using System.Collections.Generic;
using Unity.VisualScripting;

public class ControlUnit : MonoBehaviour
{
    [Header("Raw ADC (0..1023)")]
    public ushort A0;    // A0
    public ushort A1;    // A1
    public ushort A2;    // A2
    public ushort A3;    // A3
    public ushort A4;   // A4
    public ushort A5;   // A5

    [Header("Buttons (pressed = true)")]
    public bool D2;  // bit0
    public bool D3;  // bit1
    public bool D4;  // bit2
    public bool D5;  // bit3
    public bool D6;  // bit4

    [Header("Robot Actuators")]
    public Rigidbody rb;
    public List<ThrusterBehave> engine;
    public List<BrakeBehave> brake;
    public List<ServoBehave> servo;

    //! 토글 상태 저장
    private bool engineOn = false;   // 처음부터 꺼짐
    private bool prevD2 = false;

    // Start is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {
        BrakeBehave[] brakes = GetComponentsInChildren<BrakeBehave>();
        rb = this.GetComponent<Rigidbody>();
        rb.mass += brakes.Length;
    }

    // Update is called once per frame
    void FixedUpdate()
    {
        FreezeRotation();

        // 1. make 0 ~ 1023 -> -1 ~ 1
        float x = (A0 - 512f) / 512f;
        float y = (A1 - 512f) / 512f;

        // 1.5 to create 0 value
        x = Mathf.Abs(x) < 0.1f ? 0f : x;
        y = Mathf.Abs(y) < 0.1f ? 0f : y;

        // 2. joystick control
        // servo[0].controlVal = Mathf.Atan2(y, x) * Mathf.Rad2Deg;
        float ang = Mathf.Atan2(y, x) * Mathf.Rad2Deg;  // -180..180
        ang = Mathf.Clamp(ang, -90f, 90f);              // ±90° 제한
        servo[0].controlVal = ang;
        if (x == 0f && y == 0f)
        {
            // x와 y가 모두 0인 경우
            servo[1].controlVal = 0f;
            servo[2].controlVal = 0f;
        }
        else
        {
            // 둘 중 하나라도 0이 아닌 경우
            servo[1].controlVal = -90f;
            servo[2].controlVal = 90f;
        }
        // servo[3].controlVal = Mathf.Atan2(y, x) * Mathf.Rad2Deg;
        // servo[4].controlVal = Mathf.Atan2(y, x) * Mathf.Rad2Deg;
        // servo[5].controlVal = Mathf.Atan2(y, x) * Mathf.Rad2Deg;
        // servo[6].controlVal = Mathf.Atan2(y, x) * Mathf.Rad2Deg;
        // servo[7].controlVal = Mathf.Atan2(y, x) * Mathf.Rad2Deg;
        // servo[8].controlVal = Mathf.Atan2(y, x) * Mathf.Rad2Deg;
        // servo[9].controlVal = Mathf.Atan2(y, x) * Mathf.Rad2Deg;

        // Debug.Log(x + ", " + y);

        //! button toggle =================
        if (D2 && !prevD2)  // Only when button state changes from unpressed to pressed
            engineOn = !engineOn;
        prevD2 = D2;

        if (engineOn)
        {
            engine[0].controlVal = 1f;
            brake[0].controlVal = 0f;
        }
        else
        {
            engine[0].controlVal = 0f;
            brake[0].controlVal = 1f;
        }
        //! ===================================

        // if (D2)
        // {
        //     engine[0].controlVal = 0f;      // turn on engine (max)
        //     // engine[1].controlVal = 0f;      // new code
        //     // engine[2].controlVal = 0f;
        //     // engine[3].controlVal = 0f;
        //     // engine[4].controlVal = 0f;  
        //     // engine[5].controlVal = 0f;
        //     // engine[6].controlVal = 0f;
        //     // engine[7].controlVal = 0f;    
        //     // engine[8].controlVal = 0f;
        //     // engine[9].controlVal = 0f;
        //     brake[0].controlVal = 1f;       // new code for break

        //     // my idea : use Max Thrust = 60, control power according to degree
        //     // engine[0].controlVal = 0.5f - (x * 0.3f);      // faster turn
        //     // engine[1].controlVal = 0.5f + (x * 0.3f);      // same reason
        //     // brake[0].controlVal = 0f;
        // }
        // else
        // {
        //     engine[0].controlVal = 1f;      // turn off engine
        //     // engine[1].controlVal = 1f;      // new code
        //     // engine[2].controlVal = 1f;
        //     // engine[3].controlVal = 1f;
        //     // engine[4].controlVal = 1f;  
        //     // engine[5].controlVal = 1f;
        //     // engine[6].controlVal = 1f;
        //     // engine[7].controlVal = 1f;    
        //     // engine[8].controlVal = 1f;
        //     // engine[9].controlVal = 1f;
        //     brake[0].controlVal = 0f;       // new code
        // }

        // code given
        // if (D3)
        // {
        //     engine[1].controlVal = 1f;
        // }
        // else
        // {
        //     engine[1].controlVal = 0f;
        // }
    }

    private void FreezeRotation()
    {
        rb.angularVelocity = new Vector3(0f, rb.angularVelocity.y, 0f);
        Vector3 curRot = this.transform.rotation.eulerAngles;
        this.transform.rotation = Quaternion.Euler(0f, curRot.y, 0f);
        rb.linearVelocity = new Vector3(rb.linearVelocity.x, 0f, rb.linearVelocity.z);
    }
}
