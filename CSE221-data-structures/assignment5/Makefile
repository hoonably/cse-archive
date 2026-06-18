CXX=clang++
CXXFLAGS=-std=c++17

# Output target
TARGET=main

# Objects
OBJS=graph.o heap.o dijkstra.o main.o

# Default make target
all: $(TARGET)
	@rm -f $(OBJS)

# Linking
$(TARGET): $(OBJS)
	$(CXX) $(CXXFLAGS) -o $(TARGET) $(OBJS)

# Compile source: graph.cpp
graph.o: graph.h graph.cpp
	$(CXX) $(CXXFLAGS) -c graph.cpp -o graph.o

# Compile source: heap.cpp
heap.o: heap.h heap.cpp
	$(CXX) $(CXXFLAGS) -c heap.cpp -o heap.o

# Compile source: dijkstra.cpp
dijkstra.o: dijkstra.h dijkstra.cpp
	$(CXX) $(CXXFLAGS) -c dijkstra.cpp -o dijkstra.o

# Compile source: main.cpp
main.o: main.cpp
	$(CXX) $(CXXFLAGS) -c main.cpp -o main.o

# Clean up
clean:
	rm -f $(TARGET) $(OBJS)