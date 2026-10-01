#include "../production/sha256.h"
#include <stdexcept>
#include <string>
#include <iostream>

int main() {
    using hdm::production::Sha256;
    Sha256 empty;
    if (empty.FinalHex() != "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        throw std::runtime_error("empty SHA-256");
    Sha256 abc;
    abc.Update("a", 1); abc.Update("bc", 2);
    if (abc.FinalHex() != "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        throw std::runtime_error("incremental SHA-256");
    Sha256 million;
    const std::string chunk(1000, 'a');
    for (int i=0;i<1000;++i) million.Update(chunk.data(),chunk.size());
    if (million.FinalHex() != "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
        throw std::runtime_error("multi-block SHA-256");
    std::cout << "PASS sha256\n";
}
