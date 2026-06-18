/* You cannot modify this file */
#ifndef CONTAINER_EXCEPTION_H
#define CONTAINER_EXCEPTION_H

#include <exception>
#include <string>

class ContainerException : public std::exception {
protected:
    std::string message;
public:
    explicit ContainerException(const std::string& msg) : message(msg) {}
    virtual const char* what() const noexcept { return message.c_str(); }
};

class ContainerOverflow : public ContainerException {
public:
    explicit ContainerOverflow(const std::string& msg) : ContainerException(msg) {}
};

class ContainerEmpty : public ContainerException {
public:
    explicit ContainerEmpty(const std::string& msg) : ContainerException(msg) {}
};

#endif // CONTAINER_EXCEPTION_H