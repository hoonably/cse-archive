using UnityEngine;

public class gravityBehave : MonoBehaviour
{
    public float starMass;
    // Start is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {
        
    }

    // Update is called once per frame
    void Update()
    {
        
    }

    public void OnTriggerStay(Collider other)
    {
        if (other.CompareTag("Player"))
        {
            Rigidbody rb = other.GetComponent<Rigidbody>();
            Vector3 dist = this.transform.position - other.transform.position;
            rb.AddForce(starMass * rb.mass / (dist.magnitude * dist.magnitude) * dist.normalized);
        }
    }
}
