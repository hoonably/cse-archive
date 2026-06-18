using UnityEngine;
using UnityEngine.InputSystem;
using System.Collections.Generic;

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

        // contol system over here
        float x = (A0 - 512f) / 512f;
        float y = (A1 - 512f) / 512f;

        x = Mathf.Abs(x) < 0.1f ? 0f : x;
        y = Mathf.Abs(y) < 0.1f ? 0f : y;

        servo[0].controlVal = Mathf.Atan2(y, x) * Mathf.Rad2Deg;
        servo[1].controlVal = Mathf.Atan2(y, x) * Mathf.Rad2Deg;

        Debug.Log(x + ", " + y);

        if (D2)
        {
            engine[0].controlVal = 1f;
            engine[1].controlVal = 1f;
            brake[0].controlVal = 1f;
        }
        else
        {
            engine[0].controlVal = 0f;
            engine[1].controlVal = 0f;
            brake[0].controlVal = 0f;
        }
    }

    private void FreezeRotation()
    {
        rb.angularVelocity = new Vector3(0f, rb.angularVelocity.y, 0f);
        Vector3 curRot = this.transform.rotation.eulerAngles;
        this.transform.rotation = Quaternion.Euler(0f, curRot.y, 0f);
        rb.linearVelocity = new Vector3(rb.linearVelocity.x, 0f, rb.linearVelocity.z);
    }
}
