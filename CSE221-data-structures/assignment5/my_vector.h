/*
This is a simple implementation of vector class.
*/

template<class T> class my_vector {
public:
    T* arr;
    int capacity;
    int length;

    my_vector() : capacity(0), length(0) {}
    my_vector(int n) : capacity(n), length(0) {
        arr = new T[n];
    }
    my_vector(int n, const T& val) : capacity(n), length(n) {
        arr = new T[n];
        for (int i = 0; i < n; i++){
            arr[i] = val;
        }
    }
    ~my_vector(){}
    T& operator[](int i){
        return arr[i];
    }
    const T& operator[](int i) const{
        return arr[i];
    }
    int size() const{
        return length;
    }
    void push_back(const T& val){
        if (capacity == 0){
            capacity = 1;
            arr = new T[1];
        }

        if (length == capacity){
            capacity *= 2;
            T* new_arr = new T[capacity];
            for (int i = 0; i < length; i++){  // copy arr[0]~arr[length-1]
                new_arr[i] = arr[i];
            }
            delete[] arr;
            arr = new_arr;
        }
        arr[length] = val;
        length++;
    }
    void pop_back(){
        length--;
    }
};