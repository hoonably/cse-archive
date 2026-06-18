#include "device.h"
using namespace std;

/* Write your code here */

Device::Device(int id, const std::string& type, const std::string& brand)
: device_id(id), device_type(type), brand(brand) {}
Device::~Device() {}

bool Device::operator==(const Device& other) const{
    return device_id == other.device_id
    && device_type == other.device_type
    && brand == other.brand;
}
bool Device::operator<(const Device& other) const{
    return device_id < other.device_id;
}
bool Device::operator>(const Device& other) const{
    return device_id > other.device_id;
}
bool Device::operator<=(const Device& other) const{
    return device_id <= other.device_id;
}
bool Device::operator>=(const Device& other) const{
    return device_id >= other.device_id;
}

Phone::Phone(int id, const std::string& brand, int data_usage)
    : Device(id, "Phone", brand), data_usage(data_usage) {}
Phone::~Phone() {}

Watch::Watch(int id, const std::string& brand, int step_count)
    : Device(id, "Watch", brand), step_count(step_count) {}
Watch::~Watch() {}

Ring::Ring(int id, const std::string& brand, bool sleep_tracking)
    : Device(id, "Ring", brand), sleep_tracking(sleep_tracking) {}
Ring::~Ring() {}

Earbud::Earbud(int id, const std::string& brand, bool noise_cancel)
    : Device(id, "Earbud", brand), noise_cancellation(noise_cancel) {}
Earbud::~Earbud() {}

void Phone::print_device() const {
    cout << "Phone [ID: " << device_id << ", Brand: " << brand << ", Data Usage: " << data_usage << " GB]\n";
}

void Watch::print_device() const {
    cout << "Watch [ID: " << device_id << ", Brand: " << brand << ", Step Count: " << step_count << "]\n";
}

void Ring::print_device() const {
    cout << "Ring [ID: " << device_id << ", Brand: " << brand << ", Sleep Tracking: "
    << (sleep_tracking ? "Enabled" : "Disabled") << "]\n";
}

void Earbud::print_device() const {
    cout << "Earbud [ID: " << device_id << ", Brand: " << brand << ", Noise Cancellation: "
    << (noise_cancellation ? "Enabled" : "Disabled") << "]\n";
}

bool Phone::operator<(const Phone& other) const{
    return data_usage < other.data_usage;
}
bool Phone::operator>(const Phone& other) const{
    return data_usage > other.data_usage;
}
bool Phone::operator<=(const Phone& other) const{
    return data_usage <= other.data_usage;
}
bool Phone::operator>=(const Phone& other) const{
    return data_usage >= other.data_usage;
}

bool Watch::operator<(const Watch& other) const{
    return step_count < other.step_count;
}
bool Watch::operator>(const Watch& other) const{
    return step_count > other.step_count;
}
bool Watch::operator<=(const Watch& other) const{
    return step_count <= other.step_count;
}
bool Watch::operator>=(const Watch& other) const{
    return step_count >= other.step_count;
}