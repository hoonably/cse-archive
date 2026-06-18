CXX=clang++
CXXFLAGS=-std=c++17

# Output target
TARGET=main

# Objects
OBJS=student_map.o student_ordered_map.o student_database.o main.o

# Default make target
all: $(TARGET)
	@rm -f $(OBJS)

# Linking
$(TARGET): $(OBJS)
	$(CXX) $(CXXFLAGS) -o $(TARGET) $(OBJS)

# Compile source: student_map.cpp
student_map.o: student_map.h
	$(CXX) $(CXXFLAGS) -c student_map.cpp -o student_map.o

# Compile source: student_ordered_map.cpp
student_ordered_map.o: student_ordered_map.h
	$(CXX) $(CXXFLAGS) -c student_ordered_map.cpp -o student_ordered_map.o

# Compile source: student_database.cpp
student_database.o: student_database.h
	$(CXX) $(CXXFLAGS) -c student_database.cpp -o student_database.o

# Compile source: main.cpp
main.o: main.cpp
	$(CXX) $(CXXFLAGS) -c main.cpp -o main.o

# Clean up
clean:
	rm -f $(TARGET) $(OBJS)