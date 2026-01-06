#include <jni.h>
#include <android/log.h>
#include <string>
#include <vector>
#include <thread>
#include <chrono>
#include "llama.h"
#include "ggml-backend.h"

#define TAG "LlamaJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

// Convert UTF-8 string to JNI jstring safely (handles full Unicode including emojis)
static jstring utf8ToJstring(JNIEnv* env, const char* utf8, int len) {
    if (len <= 0) return env->NewStringUTF("");
    
    std::vector<jchar> utf16;
    utf16.reserve(len);
    
    const unsigned char* s = (const unsigned char*)utf8;
    const unsigned char* end = s + len;
    
    while (s < end) {
        uint32_t codepoint = 0;
        int bytes = 0;
        
        if ((*s & 0x80) == 0) {
            // ASCII
            codepoint = *s++;
        } else if ((*s & 0xE0) == 0xC0) {
            // 2-byte sequence
            if (s + 1 >= end || (s[1] & 0xC0) != 0x80) { s++; continue; }
            codepoint = ((*s & 0x1F) << 6) | (s[1] & 0x3F);
            s += 2;
        } else if ((*s & 0xF0) == 0xE0) {
            // 3-byte sequence
            if (s + 2 >= end || (s[1] & 0xC0) != 0x80 || (s[2] & 0xC0) != 0x80) { s++; continue; }
            codepoint = ((*s & 0x0F) << 12) | ((s[1] & 0x3F) << 6) | (s[2] & 0x3F);
            s += 3;
        } else if ((*s & 0xF8) == 0xF0) {
            // 4-byte sequence (emojis, etc.)
            if (s + 3 >= end || (s[1] & 0xC0) != 0x80 || (s[2] & 0xC0) != 0x80 || (s[3] & 0xC0) != 0x80) { s++; continue; }
            codepoint = ((*s & 0x07) << 18) | ((s[1] & 0x3F) << 12) | ((s[2] & 0x3F) << 6) | (s[3] & 0x3F);
            s += 4;
        } else {
            // Invalid byte, skip
            s++;
            continue;
        }
        
        // Convert codepoint to UTF-16
        if (codepoint <= 0xFFFF) {
            utf16.push_back((jchar)codepoint);
        } else if (codepoint <= 0x10FFFF) {
            // Surrogate pair for codepoints > 0xFFFF
            codepoint -= 0x10000;
            utf16.push_back((jchar)(0xD800 | (codepoint >> 10)));
            utf16.push_back((jchar)(0xDC00 | (codepoint & 0x3FF)));
        }
    }
    
    if (utf16.empty()) return env->NewStringUTF("");
    return env->NewString(utf16.data(), utf16.size());
}

static llama_model* model = nullptr;
static llama_context* ctx = nullptr;
static llama_sampler* sampler = nullptr;
static volatile bool g_should_stop = false;  // Флаг остановки генерации

extern "C" {

JNIEXPORT void JNICALL
Java_com_example_nexus_LlamaBridge_stopGeneration(JNIEnv *env, jobject thiz) {
    g_should_stop = true;
    LOGI("Stop generation requested");
}

JNIEXPORT jlong JNICALL
Java_com_example_nexus_LlamaBridge_loadModel(JNIEnv *env, jobject thiz, jstring model_path) {
    if (model != nullptr) {
        llama_model_free(model);
        model = nullptr;
    }

    const char* path = env->GetStringUTFChars(model_path, nullptr);
    LOGI("Loading model: %s", path);

    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = 0;  // CPU only
    LOGI("Using CPU backend");

    model = llama_model_load_from_file(path, model_params);
    env->ReleaseStringUTFChars(model_path, path);

    if (model == nullptr) {
        LOGE("Failed to load model");
        return 0;
    }

    LOGI("Model loaded successfully");
    return reinterpret_cast<jlong>(model);
}

JNIEXPORT jlong JNICALL
Java_com_example_nexus_LlamaBridge_createContext(JNIEnv *env, jobject thiz, jlong model_ptr) {
    if (ctx != nullptr) {
        llama_free(ctx);
        ctx = nullptr;
    }
    if (sampler != nullptr) {
        llama_sampler_free(sampler);
        sampler = nullptr;
    }

    llama_model* m = reinterpret_cast<llama_model*>(model_ptr);
    if (m == nullptr) {
        LOGE("Invalid model pointer");
        return 0;
    }

    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = 2048;
    ctx_params.n_batch = 512;
    int total_cores = (int)std::thread::hardware_concurrency();
    ctx_params.n_threads = std::max(1, total_cores - 2);  // Оставляем 2 ядра для UI
    ctx_params.n_threads_batch = ctx_params.n_threads;

    ctx = llama_init_from_model(m, ctx_params);
    if (ctx == nullptr) {
        LOGE("Failed to create context");
        return 0;
    }

    // Создаём sampler (упрощённый для скорости)
    sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
    
    // Repetition penalty
    llama_sampler_chain_add(sampler, llama_sampler_init_penalties(
        32,     // last_n - меньше окно = быстрее
        1.1f,   // repeat_penalty
        0.0f,   // frequency_penalty
        0.0f    // presence_penalty
    ));
    
    // Только top_k + temp + dist (без top_p для скорости)
    llama_sampler_chain_add(sampler, llama_sampler_init_top_k(32));
    llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.5f));
    llama_sampler_chain_add(sampler, llama_sampler_init_dist(42));

    LOGI("Context created, threads: %d", ctx_params.n_threads);
    return reinterpret_cast<jlong>(ctx);
}

JNIEXPORT jstring JNICALL
Java_com_example_nexus_LlamaBridge_generate(JNIEnv *env, jobject thiz, jstring prompt, jint max_tokens) {
    if (model == nullptr || ctx == nullptr || sampler == nullptr) {
        LOGE("Model or context not initialized");
        return env->NewStringUTF("");
    }

    const char* prompt_cstr = env->GetStringUTFChars(prompt, nullptr);
    std::string prompt_str(prompt_cstr);
    env->ReleaseStringUTFChars(prompt, prompt_cstr);

    LOGI("Generating, prompt length: %zu, max_tokens: %d", prompt_str.length(), max_tokens);

    const llama_vocab* vocab = llama_model_get_vocab(model);

    // Токенизация
    const int n_prompt_max = prompt_str.length() + 256;
    std::vector<llama_token> tokens(n_prompt_max);
    
    const int n_prompt = llama_tokenize(vocab, prompt_str.c_str(), prompt_str.length(), 
                                         tokens.data(), tokens.size(), true, true);
    if (n_prompt < 0) {
        LOGE("Tokenization failed");
        return env->NewStringUTF("");
    }
    tokens.resize(n_prompt);

    LOGI("Tokenized: %d tokens", n_prompt);

    // Сбрасываем sampler
    llama_sampler_reset(sampler);

    // Создаём batch для prompt
    llama_batch batch = llama_batch_get_one(tokens.data(), tokens.size());
    
    if (llama_decode(ctx, batch) != 0) {
        LOGE("Decode failed");
        return env->NewStringUTF("");
    }

    // Генерация
    std::string result;
    int n_generated = 0;

    while (n_generated < max_tokens) {
        llama_token new_token = llama_sampler_sample(sampler, ctx, -1);

        if (llama_vocab_is_eog(vocab, new_token)) {
            LOGI("EOS token reached");
            break;
        }

        char buf[256] = {0};
        int n = llama_token_to_piece(vocab, new_token, buf, sizeof(buf) - 1, 0, true);
        if (n > 0 && n < (int)sizeof(buf)) {
            buf[n] = '\0';
            result.append(buf);
        }

        // Декодируем новый токен
        llama_batch single = llama_batch_get_one(&new_token, 1);
        if (llama_decode(ctx, single) != 0) {
            LOGE("Decode failed during generation");
            break;
        }

        n_generated++;
    }

    LOGI("Generated %d tokens, result length: %zu", n_generated, result.length());
    return utf8ToJstring(env, result.c_str(), result.length());
}

// Проверяет содержит ли текст стоп-строку
static bool contains_stop_string(const std::string& text) {
    static const char* stop_strings[] = {
        "Отвечай на русском",
        "<|eot_id|>",
        "<|start_header_id|>",
        "<|im_end|>",
        "<|im_start|>",
        "<|end|>",
        "<|user|>",
        "</s>",
        "[INST]",
        "<end_of_turn>",
        "<start_of_turn>",
        nullptr
    };
    
    for (int i = 0; stop_strings[i] != nullptr; i++) {
        if (text.find(stop_strings[i]) != std::string::npos) {
            return true;
        }
    }
    return false;
}

JNIEXPORT jboolean JNICALL
Java_com_example_nexus_LlamaBridge_generateWithCallback(JNIEnv *env, jobject thiz, jstring prompt, jint max_tokens, jobject callback) {
    if (model == nullptr || ctx == nullptr || sampler == nullptr) {
        LOGE("Model or context not initialized");
        return JNI_FALSE;
    }

    // Получаем метод callback
    jclass callbackClass = env->GetObjectClass(callback);
    jmethodID onTokenMethod = env->GetMethodID(callbackClass, "onToken", "(Ljava/lang/String;)V");
    if (onTokenMethod == nullptr) {
        LOGE("Failed to get onToken method");
        return JNI_FALSE;
    }

    const char* prompt_cstr = env->GetStringUTFChars(prompt, nullptr);
    std::string prompt_str(prompt_cstr);
    env->ReleaseStringUTFChars(prompt, prompt_cstr);

    LOGI("Generating with streaming, prompt length: %zu, max_tokens: %d", prompt_str.length(), max_tokens);

    // Получаем vocab из model
    const llama_vocab* vocab = llama_model_get_vocab(model);

    // Токенизация
    const int n_prompt_max = prompt_str.length() + 256;
    std::vector<llama_token> tokens(n_prompt_max);
    
    const int n_prompt = llama_tokenize(vocab, prompt_str.c_str(), prompt_str.length(), 
                                         tokens.data(), tokens.size(), true, true);
    if (n_prompt < 0) {
        LOGE("Tokenization failed");
        return JNI_FALSE;
    }
    tokens.resize(n_prompt);

    LOGI("Tokenized: %d tokens", n_prompt);

    // Сбрасываем sampler
    llama_sampler_reset(sampler);

    // Создаём batch для prompt
    llama_batch batch = llama_batch_get_one(tokens.data(), tokens.size());
    
    if (llama_decode(ctx, batch) != 0) {
        LOGE("Decode failed");
        return JNI_FALSE;
    }

    // Генерация с callback для каждого токена
    int n_generated = 0;
    auto start_time = std::chrono::high_resolution_clock::now();
    g_should_stop = false;  // Сбрасываем флаг остановки
    std::string accumulated;  // Накапливаем текст для проверки стоп-строк

    while (n_generated < max_tokens) {
        // Проверяем флаг остановки
        if (g_should_stop) {
            LOGI("Generation stopped by user");
            break;
        }
        
        llama_token new_token = llama_sampler_sample(sampler, ctx, -1);

        if (llama_vocab_is_eog(vocab, new_token)) {
            LOGI("EOS token reached");
            break;
        }

        char buf[256] = {0};
        int n = llama_token_to_piece(vocab, new_token, buf, sizeof(buf) - 1, 0, true);
        if (n > 0 && n < (int)sizeof(buf)) {
            buf[n] = '\0';
            accumulated.append(buf);
            
            // Проверяем стоп-строки в накопленном тексте
            if (contains_stop_string(accumulated)) {
                LOGI("Stop string detected, stopping generation");
                break;
            }
            
            // Отправляем токен через callback (используем utf8ToJstring для поддержки эмодзи)
            jstring tokenStr = utf8ToJstring(env, buf, n);
            if (tokenStr != nullptr) {
                env->CallVoidMethod(callback, onTokenMethod, tokenStr);
                env->DeleteLocalRef(tokenStr);
            }
        }

        // Декодируем новый токен
        llama_batch single = llama_batch_get_one(&new_token, 1);
        if (llama_decode(ctx, single) != 0) {
            LOGE("Decode failed during generation");
            break;
        }

        n_generated++;
    }

    auto end_time = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time).count();
    float tokens_per_sec = (duration > 0) ? (n_generated * 1000.0f / duration) : 0;
    LOGI("Generated %d tokens in %lld ms (%.2f tokens/sec)", n_generated, duration, tokens_per_sec);
    return JNI_TRUE;
}

JNIEXPORT void JNICALL
Java_com_example_nexus_LlamaBridge_unload(JNIEnv *env, jobject thiz) {
    LOGI("Unloading model");
    
    if (sampler != nullptr) {
        llama_sampler_free(sampler);
        sampler = nullptr;
    }
    if (ctx != nullptr) {
        llama_free(ctx);
        ctx = nullptr;
    }
    if (model != nullptr) {
        llama_model_free(model);
        model = nullptr;
    }
}

JNIEXPORT void JNICALL
Java_com_example_nexus_LlamaBridge_initBackend(JNIEnv *env, jobject thiz) {
    LOGI("Initializing llama backend");
    llama_backend_init();
}

}
