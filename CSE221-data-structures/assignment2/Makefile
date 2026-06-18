# Example Makefile. This compiles the program correctly once manager.cpp and device.cpp are implemented correctly.
# Note that "make" command must generate C++ program "main".
# Feel free to modify this file.

CXX=clang++
CXXFLAGS=-std=c++17

# Output target
TARGET=main

# Objects
OBJS=device.o manager.o main.o

# Default make target
all: $(TARGET)
	@rm -f $(OBJS)

# Linking
$(TARGET): $(OBJS)
	$(CXX) $(CXXFLAGS) -o $(TARGET) $(OBJS)

# Compile source: device.cpp
device.o: device.cpp
	$(CXX) $(CXXFLAGS) -c device.cpp -o device.o

# Compile source: manager.cpp
manager.o: manager.cpp
	$(CXX) $(CXXFLAGS) -c manager.cpp -o manager.o

# Compile source: main.cpp
main.o: main.cpp
	$(CXX) $(CXXFLAGS) -c main.cpp -o main.o

# Clean up
clean:
	rm -f $(TARGET) $(OBJS)