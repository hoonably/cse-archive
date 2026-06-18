#ifndef DEVICE_H
#define DEVICE_H

#include <iostream>
#include <string>

class Device {
protected:
    int device_id;
    std::string device_type;
    std::string brand;

public:
    Device(int id, const std::string& type, const std::string& brand);

    virtual ~Device();
    virtual void print_device() const = 0;

    bool operator==(const Device& other) const;
    bool operator<(const Device& other) const;
    bool operator>(const Device& other) const;
    bool operator<=(const Device& other) const;
    bool operator>=(const Device& other) const;
};


class Phone : public Device {
private:
    int data_usage; // Mobile data usage in GB

public:
    Phone(int id, const std::string& brand, int data_usage);
    ~Phone();
    void print_device() const;

    bool operator<(const Phone& other) const;
    bool operator>(const Phone& other) const;
    bool operator<=(const Phone& other) const;
    bool operator>=(const Phone& other) const;
};

class Watch : public Device {
private:
    int step_count; // Step counter function

public:
    Watch(int id, const std::string& brand, int step_count);
    ~Watch();
    void print_device() const;

    bool operator<(const Watch& other) const;
    bool operator>(const Watch& other) const;
    bool operator<=(const Watch& other) const;
    bool operator>=(const Watch& other) const;
};

class Ring : public Device {
private:
    bool sleep_tracking ;  // Sleep quality measurement

public:
    Ring(int id, const std::string& brand, bool sleep_tracking);
    ~Ring();
    void print_device() const;
};

class Earbud : public Device {
private:
    bool noise_cancellation;  // Whether the earbuds have noise cancellation

public:
    Earbud(int id, const std::string& brand, bool noise_cancel);
    ~Earbud();
    void print_device() const;
};

#endif