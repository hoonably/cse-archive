/* You cannot modify this file */
#ifndef MANAGER_H
#define MANAGER_H

#include "device.h"
#include <exception>
#include <string>

const int MAX_DEVICES = 100;  // Maximum number of devices

// Exception class for duplicate devices
class DuplicateDevice : public std::exception {
    const Device* device;  // Pointer to the device that caused the exception

public:
    // Constructor to initialize with the duplicate device
    explicit DuplicateDevice(const Device* device)
        : device(device) {}

    // Override the what() method to return the error message
    const char* what() const noexcept {
        return "Duplicate device detected:";
    }

    // Additional method to print the device info
    void print_device_info() const {
        if (device) {
            device->print_device();  // Directly call print_device() on the device
        }
    }
};

class Manager {
private:
    Device* devices[MAX_DEVICES];  // Fixed-size array to store pointers to devices
    int device_count;              // Current count of devices

public:
    Manager();
    void add_device(Device* device);
    bool compare_device(int index, const Device& other) const;
    Device* find_device(const Device& search_device) const;
    void delete_device(const Device& device);
    void print_all_devices() const;
    ~Manager();
};

#endif