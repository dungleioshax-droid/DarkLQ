//
//  il2cpp.h
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/6/26.
//

#ifndef il2cpp_h
#define il2cpp_h

#ifdef __cplusplus

#include <vector>

struct Il2CppClass;

template <typename T> struct Il2CppArray {
    Il2CppClass *klass; // 0x00
    void *bounds;       // 0x08
    uint64_t length;    // 0x10
    T m_Items[1];       // 0x18

    T *getPointer() { return (T *)m_Items; }

    uint64_t getLength() { return length; }

    T &operator[](int i) { return m_Items[i]; }

    T &operator[](int i) const { return m_Items[i]; }

    std::vector<T> toCPPlist() {
        std::vector<T> ret;
        ret.reserve(length);

        for (int i = 0; i < length; i++) {
            ret.push_back(m_Items[i]);
        }

        return ret;
    }
};

template <typename T> using Array = Il2CppArray<T>;

template <typename T> struct Il2CppList {
    Il2CppClass *klass;      // 0x00
    Il2CppArray<T> *items;   // 0x08
    int size;                // 0x10
    int version;             // 0x14
    void *syncRootOrUnknown; // 0x18

    T *getItems() { return items ? items->getPointer() : nullptr; }

    int getSize() { return size; }

    int getVersion() { return version; }

    T &operator[](int i) { return items->m_Items[i]; }

    T &operator[](int i) const { return items->m_Items[i]; }

    std::vector<T> toCPPlist() {
        std::vector<T> ret;
        ret.reserve(size); // Reserve space in the vector for the items.

        for (int i = 0; i < size; i++) {
            ret.push_back(items->m_Items[i]);
        }

        return ret;
    }
};

template <typename T> using List = Il2CppList<T>;

template <typename K, typename V> struct Il2CppDictionary {
    Il2CppClass *klass;
    void *unk1;
    Il2CppArray<int **> *table;
    Il2CppArray<void **> *linkSlots;
    Il2CppArray<K> *keys;
    Il2CppArray<V> *values;
    int touchedSlots;
    int emptySlot;
    int size;

    K *getKeys() { return keys->getPointer(); }

    V *getValues() { return values->getPointer(); }

    int getNumKeys() { return keys->getLength(); }

    int getNumValues() { return values->getLength(); }

    int getSize() { return size; }
};

template <typename K, typename V> using Dictionary = Il2CppDictionary<K, V>;

template <typename T> struct Il2CppPoolObjHandle {
    union {
        uint32_t _handleSeq; // 0x00
        T *_handleObj;       // 0x00 (overlap _handleSeq)
    };

    bool HasValue() const { return _handleObj != nullptr && _handleSeq != 0; }

    T *GetHandle() const { return _handleObj; }

    T *operator->() const { return _handleObj; }

    T &operator*() const { return *_handleObj; }

    explicit operator bool() const { return HasValue(); }
};

template <typename T> using PoolObjHandle = Il2CppPoolObjHandle<T>;

#endif // __cplusplus

#endif /* il2cpp_h */
