using UnityEngine;

public class ResourceBehave : MonoBehaviour
{
    // Start is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {
        
    }

    // Update is called once per frame
    void Update()
    {
        
    }

    private void OnTriggerEnter(Collider other)
    {
        if (other.CompareTag("Player") && (other.GetComponent<ControlUnit>() || other.GetComponent<DroneControlUnit>()))
        {
            this.transform.parent.gameObject.SetActive(false);
            TimerBehave.Instance.getResource(this);
        }
    }
}
