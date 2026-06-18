CXX=clang++
CXXFLAGS=-std=c++17

# Output target
TARGET=main

# Objects
OBJS=doubly_linked_list.o stack.o deque.o main.o

# Default make target
all: $(TARGET)
	@rm -f $(OBJS)

# Linking
$(TARGET): $(OBJS)
	$(CXX) $(CXXFLAGS) -o $(TARGET) $(OBJS)

# Compile source: doubly_linked_list.cpp
doubly_linked_list.o: doubly_linked_list.cpp
	$(CXX) $(CXXFLAGS) -c doubly_linked_list.cpp -o doubly_linked_list.o

# Compile source: stack.cpp
stack.o: stack.cpp
	$(CXX) $(CXXFLAGS) -c stack.cpp -o stack.o

# Compile source: deque.cpp
deque.o: deque.cpp
	$(CXX) $(CXXFLAGS) -c deque.cpp -o deque.o

# Compile source: main.cpp
main.o: main.cpp
	$(CXX) $(CXXFLAGS) -c main.cpp -o main.o

# Clean up
clean:
	rm -f $(TARGET) $(OBJS)