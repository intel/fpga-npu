#include "utils.h"

// Operator overload for printing a vector
template <typename T>
std::ostream& operator<< (std::ostream& out, const std::vector<T>& v) {
    out << "{";
    size_t last = v.size() - 1;
    for(size_t i = 0; i < v.size(); ++i) {
        out << v[i];
        if (i != last)
            out << ", ";
    }
    out << "}";
    return out;
}

// Used for populating vector register file contents from a file
void readVectorFile(std::string &file_name, std::vector<std::vector<TYPE>> &vec_data) {
    std::ifstream in(file_name);

    if (!in) assert(0 && "file not open");
    std::string line;
    while(std::getline(in, line)) {
        std::stringstream line_stream(line);
        std::vector<TYPE> data;
        TYPE temp;
        while (line_stream >> temp) {
            data.push_back(temp);
        }
        vec_data.push_back(data);
    }
}

// Used for populating vector FIFO contents from a file
void readVectorFile(std::string &file_name, std::queue<std::vector<TYPE>> &que_data) {
    std::ifstream in(file_name);
    if (!in) assert(0 && "file not open");
    std::string line;
    while(std::getline(in, line)) {
        std::stringstream line_stream(line);
        std::vector<TYPE> data;
        TYPE temp;
        while (line_stream >> temp) {
            data.push_back(temp);
        }
        que_data.push(data);
    }
}

// Operator overload for adding two vectors
std::vector<TYPE> operator+ (const std::vector<TYPE> &v1, const std::vector<TYPE> &v2){
    assert(v1.size() == v2.size() && "The two vectors have different lengths");
    std::vector<TYPE> result;
    for(unsigned int i = 0; i < v1.size(); i++){
        result.push_back(v1[i] + v2[i]);
    }
    return result;
}

// Used for reading simulating golden outputs
template <typename T>
void readGoldenOutput(std::string &file_name, std::vector<T> &vec_data, int v_size) {
    std::ifstream in(file_name);

    if (!in) assert(0 && "file not open");
    std::string line;
    while(std::getline(in, line)) {
        std::stringstream line_stream(line);
        std::vector<TYPE> data;
        TYPE temp;
        int count = 0;
        while (line_stream >> temp) {
            data.push_back(temp);
            count++;
            if(count == v_size){
                count = 0;
                vec_data.push_back(data);
                data.erase(data.begin(), data.end());
            }
        }
    }
}

template std::ostream& operator<< (std::ostream& out, const std::vector<TYPE>& v);
template void readGoldenOutput(std::string &file_name, std::vector<std::vector<TYPE>> &vec_data, 
    int v_size);