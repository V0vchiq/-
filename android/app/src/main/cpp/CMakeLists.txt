cmake_minimum_required(VERSION 3.22.1)
project(llama-android)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Скачиваем llama.cpp только для заголовков (без сборки)
include(FetchContent)
FetchContent_Declare(
    llama
    GIT_REPOSITORY https://github.com/ggerganov/llama.cpp.git
    GIT_TAG master
)
# Только скачиваем, НЕ добавляем в сборку
FetchContent_GetProperties(llama)
if(NOT llama_POPULATED)
    FetchContent_Populate(llama)
endif()

# Путь к pre-built библиотекам
set(PREBUILT_DIR ${CMAKE_SOURCE_DIR}/../jniLibs/${ANDROID_ABI})

# Импортируем pre-built библиотеки
add_library(prebuilt-llama SHARED IMPORTED)
set_target_properties(prebuilt-llama PROPERTIES IMPORTED_LOCATION ${PREBUILT_DIR}/libllama.so)

add_library(prebuilt-ggml SHARED IMPORTED)
set_target_properties(prebuilt-ggml PROPERTIES IMPORTED_LOCATION ${PREBUILT_DIR}/libggml.so)

add_library(prebuilt-ggml-base SHARED IMPORTED)
set_target_properties(prebuilt-ggml-base PROPERTIES IMPORTED_LOCATION ${PREBUILT_DIR}/libggml-base.so)

add_library(prebuilt-ggml-cpu SHARED IMPORTED)
set_target_properties(prebuilt-ggml-cpu PROPERTIES IMPORTED_LOCATION ${PREBUILT_DIR}/libggml-cpu.so)

# JNI библиотека
add_library(llama-android SHARED llama_jni.cpp)

target_include_directories(llama-android PRIVATE
    ${llama_SOURCE_DIR}/include
    ${llama_SOURCE_DIR}/ggml/include
)

target_link_libraries(llama-android
    prebuilt-llama
    prebuilt-ggml
    prebuilt-ggml-base
    prebuilt-ggml-cpu
    android
    log
)
