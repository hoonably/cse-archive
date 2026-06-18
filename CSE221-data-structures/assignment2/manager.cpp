#include "manager.h"

/* Write your code here */

Manager::Manager(){
    device_count = 0;
}

void Manager::add_device(Device* device){
    // 이미 디바이스가 있다면 DuplicateDevice exception
    for(int i=0; i<device_count; i++){
        if (*devices[i] == *device) {
            throw DuplicateDevice(device);
        }
    }
    devices[device_count++] = device;
}
bool Manager::compare_device(int index, const Device& other) const{
    return *devices[index] == other;
}
Device* Manager::find_device(const Device& search_device) const{
    for(int i=0; i<device_count; i++){
        if (*devices[i] == search_device) {
            return devices[i];
        }
    }
    return nullptr;
    // return devices[device_count]; // last if there is no such iterator???
}
void Manager::delete_device(const Device& device){
    for (int i = 0; i < device_count; i++) {
        if (*devices[i] == device) {
            delete devices[i];

            // 배열 빈 공간 없애기
            for (int j = i+1; j < device_count; j++) {
                devices[j-1] = devices[j];  // 이전거로 채움
            }
            device_count--;

            return;
        }
    }
}
void Manager::print_all_devices() const{
    for (int i = 0; i < device_count; i++) {
        devices[i]->print_device();
    }
}
Manager::~Manager(){
    for (int i = 0; i < device_count; i++) {
        delete devices[i];
    }
    device_count = 0;
}