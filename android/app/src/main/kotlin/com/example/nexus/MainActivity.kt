package com.example.nexus

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.StatFs
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class MainActivity : FlutterActivity() {
    private val llamaChannelName = "nexus/llama"
    private val llamaStreamChannelName = "nexus/llama/stream"
    private val downloadChannelName = "nexus/download"
    private val downloadProgressChannelName = "nexus/download/progress"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var llamaBridge: LlamaBridge? = null
    private var streamEventSink: EventChannel.EventSink? = null
    private var downloadEventSink: EventChannel.EventSink? = null
    private var currentRequestId: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        llamaBridge = LlamaBridge()
        
        // Event Channel для стриминга токенов
        EventChannel(messenger, llamaStreamChannelName).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                streamEventSink = events
            }
            override fun onCancel(arguments: Any?) {
                streamEventSink = null
            }
        })
        
        // Llama Channel
        MethodChannel(messenger, llamaChannelName).setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            when (call.method) {
                "loadModel" -> {
                    val arguments = call.arguments as? Map<*, *>
                    scope.launch {
                        try {
                            val loaded = llamaBridge?.loadModel(arguments) ?: false
                            if (loaded) {
                                result.success(true)
                            } else {
                                result.error("LOAD_ERROR", "Failed to load GGUF model", null)
                            }
                        } catch (error: Throwable) {
                            result.error("LOAD_EXCEPTION", error.localizedMessage, null)
                        }
                    }
                }

                "unloadModel" -> {
                    scope.launch {
                        try {
                            llamaBridge?.unload()
                            result.success(true)
                        } catch (error: Throwable) {
                            result.error("UNLOAD_EXCEPTION", error.localizedMessage, null)
                        }
                    }
                }

                "generate" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val prompt = arguments?.get("prompt") as? String
                    if (prompt.isNullOrBlank()) {
                        result.error("INVALID_INPUT", "Prompt is required", null)
                        return@setMethodCallHandler
                    }
                    scope.launch {
                        try {
                            // Генерация без стриминга - возвращает полную строку
                            val response = llamaBridge?.generateSync(prompt)
                            result.success(response)
                        } catch (error: Throwable) {
                            result.error("GENERATE_EXCEPTION", error.localizedMessage, null)
                        }
                    }
                }

                "generateStream" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val prompt = arguments?.get("prompt") as? String
                    val requestId = arguments?.get("requestId") as? String
                    if (prompt.isNullOrBlank() || requestId.isNullOrBlank()) {
                        result.error("INVALID_INPUT", "Prompt and requestId are required", null)
                        return@setMethodCallHandler
                    }
                    
                    // Устанавливаем текущий requestId
                    currentRequestId = requestId
                    
                    scope.launch {
                        try {
                            llamaBridge?.generateStream(prompt) { token ->
                                // Отправляем токен только если requestId совпадает
                                if (currentRequestId == requestId) {
                                    scope.launch(Dispatchers.Main) {
                                        streamEventSink?.success(mapOf(
                                            "requestId" to requestId,
                                            "token" to token
                                        ))
                                    }
                                }
                            }
                            result.success(true)
                        } catch (error: Throwable) {
                            result.error("GENERATE_EXCEPTION", error.localizedMessage, null)
                        }
                    }
                }

                "stopGeneration" -> {
                    llamaBridge?.stop()
                    currentRequestId = null
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
        
        // Event Channel для прогресса загрузки
        EventChannel(messenger, downloadProgressChannelName).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                downloadEventSink = events
                DownloadService.setProgressCallback { modelId, progress, status ->
                    scope.launch {
                        downloadEventSink?.success(mapOf(
                            "modelId" to modelId,
                            "progress" to progress,
                            "status" to status
                        ))
                    }
                }
            }
            override fun onCancel(arguments: Any?) {
                downloadEventSink = null
                DownloadService.setProgressCallback(null)
            }
        })
        
        // Download Channel
        MethodChannel(messenger, downloadChannelName).setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            when (call.method) {
                "startDownload" -> {
                    val args = call.arguments as? Map<*, *>
                    val modelId = args?.get("modelId") as? String
                    val modelName = args?.get("modelName") as? String
                    val modelUrl = args?.get("modelUrl") as? String
                    val modelSize = (args?.get("modelSize") as? Number)?.toLong() ?: 0L
                    
                    if (modelId == null || modelUrl == null) {
                        result.error("INVALID_ARGS", "modelId and modelUrl required", null)
                        return@setMethodCallHandler
                    }
                    
                    val intent = Intent(this, DownloadService::class.java).apply {
                        action = DownloadService.ACTION_START
                        putExtra(DownloadService.EXTRA_MODEL_ID, modelId)
                        putExtra(DownloadService.EXTRA_MODEL_NAME, modelName ?: modelId)
                        putExtra(DownloadService.EXTRA_MODEL_URL, modelUrl)
                        putExtra(DownloadService.EXTRA_MODEL_SIZE, modelSize)
                    }
                    startService(intent)
                    result.success(true)
                }
                
                "cancelDownload" -> {
                    val intent = Intent(this, DownloadService::class.java).apply {
                        action = DownloadService.ACTION_CANCEL
                    }
                    startService(intent)
                    result.success(true)
                }
                
                "isDownloading" -> {
                    result.success(DownloadService.isDownloading)
                }
                
                "getDownloadProgress" -> {
                    result.success(mapOf(
                        "isDownloading" to DownloadService.isDownloading,
                        "progress" to DownloadService.currentProgress,
                        "modelId" to DownloadService.currentModelId
                    ))
                }
                
                "isModelDownloaded" -> {
                    val modelId = call.arguments as? String
                    if (modelId == null) {
                        result.error("INVALID_ARGS", "modelId required", null)
                        return@setMethodCallHandler
                    }
                    Log.d("ModelCheck", "Checking model: $modelId, filesDir: ${filesDir.absolutePath}")
                    
                    // Проверяем новый путь
                    val modelFile = File(File(filesDir, "models"), "$modelId.gguf")
                    Log.d("ModelCheck", "New path: ${modelFile.absolutePath}, exists: ${modelFile.exists()}")
                    if (modelFile.exists()) {
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    
                    // Проверяем старый путь для gemma (Flutter path_provider)
                    if (modelId == "gemma2-2b-q5km") {
                        // getApplicationSupportDirectory() на Android = filesDir
                        val oldPath = File(filesDir, "llama/gemma-2-2b-it/gemma-2-2b-it-q5_k_m.gguf")
                        Log.d("ModelCheck", "Old path: ${oldPath.absolutePath}, exists: ${oldPath.exists()}")
                        
                        // Также проверим app_flutter (альтернативный путь Flutter)
                        val altPath = File(filesDir.parentFile, "app_flutter/llama/gemma-2-2b-it/gemma-2-2b-it-q5_k_m.gguf")
                        Log.d("ModelCheck", "Alt path: ${altPath.absolutePath}, exists: ${altPath.exists()}")
                        
                        result.success(oldPath.exists() || altPath.exists())
                    } else {
                        result.success(false)
                    }
                }
                
                "getModelPath" -> {
                    val modelId = call.arguments as? String
                    if (modelId == null) {
                        result.error("INVALID_ARGS", "modelId required", null)
                        return@setMethodCallHandler
                    }
                    // Проверяем новый путь
                    val modelFile = File(File(filesDir, "models"), "$modelId.gguf")
                    if (modelFile.exists()) {
                        result.success(modelFile.absolutePath)
                        return@setMethodCallHandler
                    }
                    // Проверяем старые пути для gemma
                    if (modelId == "gemma2-2b-q5km") {
                        val oldPath = File(filesDir, "llama/gemma-2-2b-it/gemma-2-2b-it-q5_k_m.gguf")
                        if (oldPath.exists()) {
                            result.success(oldPath.absolutePath)
                            return@setMethodCallHandler
                        }
                        val altPath = File(filesDir.parentFile, "app_flutter/llama/gemma-2-2b-it/gemma-2-2b-it-q5_k_m.gguf")
                        if (altPath.exists()) {
                            result.success(altPath.absolutePath)
                            return@setMethodCallHandler
                        }
                    }
                    result.success(null)
                }
                
                "deleteModel" -> {
                    val modelId = call.arguments as? String
                    if (modelId == null) {
                        result.error("INVALID_ARGS", "modelId required", null)
                        return@setMethodCallHandler
                    }
                    val modelFile = File(File(filesDir, "models"), "$modelId.gguf")
                    if (modelFile.exists()) {
                        result.success(modelFile.delete())
                    } else {
                        result.success(true)
                    }
                }
                
                else -> result.notImplemented()
            }
        }
        
        // System Info Channel
        MethodChannel(messenger, "nexus/system").setMethodCallHandler { call, result ->
            when (call.method) {
                "getMemoryInfo" -> {
                    try {
                        // Информация о хранилище
                        val statFs = StatFs(filesDir.absolutePath)
                        val totalStorage = statFs.totalBytes
                        val freeStorage = statFs.availableBytes
                        
                        // Информация об оперативной памяти
                        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        val memInfo = ActivityManager.MemoryInfo()
                        activityManager.getMemoryInfo(memInfo)
                        val totalRam = memInfo.totalMem
                        val freeRam = memInfo.availMem
                        
                        result.success(mapOf(
                            "totalStorage" to totalStorage,
                            "freeStorage" to freeStorage,
                            "totalRam" to totalRam,
                            "freeRam" to freeRam
                        ))
                    } catch (e: Exception) {
                        result.error("MEMORY_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        llamaBridge?.close()
    }
}

/**
 * LlamaBridge - нативный мост для llama.cpp
 */
class LlamaBridge {
    private val ioDispatcher = Dispatchers.IO
    private val lock = Any()
    private var isLoaded = false
    private var modelPtr: Long = 0
    private var contextPtr: Long = 0

    companion object {
        private const val TAG = "LlamaBridge"
        private const val MAX_NEW_TOKENS = 400
        
        init {
            try {
                // Загружаем зависимости в правильном порядке
                System.loadLibrary("ggml-base")
                Log.d(TAG, "ggml-base loaded")
                System.loadLibrary("ggml-cpu")
                Log.d(TAG, "ggml-cpu loaded")
                System.loadLibrary("ggml-vulkan")
                Log.d(TAG, "ggml-vulkan loaded")
                System.loadLibrary("ggml")
                Log.d(TAG, "ggml loaded")
                System.loadLibrary("llama")
                Log.d(TAG, "llama loaded")
                System.loadLibrary("llama-android")
                Log.d(TAG, "llama-android library loaded")
            } catch (e: UnsatisfiedLinkError) {
                Log.e(TAG, "Failed to load libraries", e)
            }
        }
    }

    // JNI методы - должны соответствовать C++ коду
    external fun loadModel(modelPath: String): Long
    external fun createContext(modelPtr: Long): Long
    external fun generate(prompt: String, maxTokens: Int): String?
    external fun generateWithCallback(prompt: String, maxTokens: Int, callback: TokenCallback): Boolean
    external fun stopGeneration()
    external fun unload()
    external fun initBackend()
    
    // Callback интерфейс для стриминга токенов
    fun interface TokenCallback {
        fun onToken(token: String)
    }

    suspend fun loadModel(arguments: Map<*, *>?): Boolean = withContext(ioDispatcher) {
        val modelPath = arguments?.get("modelPath") as? String ?: return@withContext false
        val modelFile = File(modelPath)
        if (!modelFile.exists()) {
            Log.e(TAG, "Model file missing: $modelPath")
            return@withContext false
        }

        synchronized(lock) {
            closeLocked()
            try {
                Log.d(TAG, "Loading model: $modelPath")
                initBackend()
                
                modelPtr = loadModel(modelPath)
                if (modelPtr == 0L) {
                    Log.e(TAG, "Failed to load model")
                    return@synchronized false
                }
                
                contextPtr = createContext(modelPtr)
                if (contextPtr == 0L) {
                    Log.e(TAG, "Failed to create context")
                    unload()
                    modelPtr = 0
                    return@synchronized false
                }
                
                isLoaded = true
                Log.d(TAG, "Model loaded successfully")
                true
            } catch (error: Exception) {
                Log.e(TAG, "Failed to initialize llama.cpp", error)
                closeLocked()
                false
            }
        }
    }

    suspend fun generateSync(prompt: String): String? = withContext(ioDispatcher) {
        if (!isLoaded) {
            Log.w(TAG, "Model not loaded")
            return@withContext null
        }

        synchronized(lock) {
            try {
                Log.d(TAG, "Generating response...")
                val result = generate(prompt, MAX_NEW_TOKENS)
                Log.d(TAG, "Generated: ${result?.take(100)}...")
                result?.trim()?.ifEmpty { null }
            } catch (error: Exception) {
                Log.e(TAG, "Generation failed", error)
                null
            }
        }
    }

    suspend fun generateStream(prompt: String, onToken: (String) -> Unit) = withContext(ioDispatcher) {
        if (!isLoaded) {
            Log.w(TAG, "Model not loaded")
            return@withContext
        }

        synchronized(lock) {
            try {
                Log.d(TAG, "Generating response with streaming...")
                generateWithCallback(prompt, MAX_NEW_TOKENS) { token ->
                    onToken(token)
                }
                onToken("[DONE]")
                Log.d(TAG, "Generation completed")
            } catch (error: Exception) {
                Log.e(TAG, "Generation failed", error)
                onToken("[ERROR]")
            }
        }
    }

    fun close() {
        synchronized(lock) {
            closeLocked()
        }
    }

    fun stop() {
        stopGeneration()
    }

    private fun closeLocked() {
        isLoaded = false
        runCatching { unload() }
        modelPtr = 0
        contextPtr = 0
    }
}
