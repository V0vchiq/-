package com.example.nexus

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

class DownloadService : Service() {
    
    companion object {
        private const val TAG = "DownloadService"
        private const val CHANNEL_ID = "nexus_download_channel"
        private const val NOTIFICATION_ID = 1001
        
        const val ACTION_START = "com.example.nexus.START_DOWNLOAD"
        const val ACTION_CANCEL = "com.example.nexus.CANCEL_DOWNLOAD"
        
        const val EXTRA_MODEL_ID = "model_id"
        const val EXTRA_MODEL_NAME = "model_name"
        const val EXTRA_MODEL_URL = "model_url"
        const val EXTRA_MODEL_SIZE = "model_size"
        
        var isDownloading = false
        var currentProgress = 0.0
        var currentModelId: String? = null
        
        private var progressCallback: ((String, Double, String) -> Unit)? = null
        
        fun setProgressCallback(callback: ((String, Double, String) -> Unit)?) {
            progressCallback = callback
        }
    }
    
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var downloadJob: Job? = null
    
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val modelId = intent.getStringExtra(EXTRA_MODEL_ID) ?: return START_NOT_STICKY
                val modelName = intent.getStringExtra(EXTRA_MODEL_NAME) ?: "Model"
                val modelUrl = intent.getStringExtra(EXTRA_MODEL_URL) ?: return START_NOT_STICKY
                val modelSize = intent.getLongExtra(EXTRA_MODEL_SIZE, 0)
                
                startDownload(modelId, modelName, modelUrl, modelSize)
            }
            ACTION_CANCEL -> {
                cancelDownload()
            }
        }
        return START_NOT_STICKY
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Загрузка моделей",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Уведомления о загрузке AI моделей"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }
    
    private fun startDownload(modelId: String, modelName: String, url: String, totalSize: Long) {
        if (isDownloading) {
            Log.w(TAG, "Download already in progress")
            return
        }
        
        isDownloading = true
        currentModelId = modelId
        currentProgress = 0.0
        
        val notification = createNotification(modelName, 0)
        startForeground(NOTIFICATION_ID, notification)
        
        downloadJob = scope.launch {
            try {
                downloadFile(modelId, modelName, url, totalSize)
            } catch (e: CancellationException) {
                Log.d(TAG, "Download cancelled")
                notifyProgress(modelId, -1.0, "cancelled")
            } catch (e: Exception) {
                Log.e(TAG, "Download failed", e)
                notifyProgress(modelId, -1.0, "error: ${e.message}")
            } finally {
                isDownloading = false
                currentModelId = null
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
    }
    
    private suspend fun downloadFile(modelId: String, modelName: String, urlString: String, expectedSize: Long) {
        val modelsDir = File(filesDir, "models")
        if (!modelsDir.exists()) modelsDir.mkdirs()
        
        val outputFile = File(modelsDir, "$modelId.gguf")
        val tempFile = File(modelsDir, "$modelId.gguf.tmp")
        
        val maxRetries = 3
        var attempt = 0
        var lastException: Exception? = null
        
        while (attempt < maxRetries) {
            attempt++
            var connection: HttpURLConnection? = null
            
            try {
                val downloadedSoFar = if (tempFile.exists()) tempFile.length() else 0L
                
                val url = URL(urlString)
                connection = url.openConnection() as HttpURLConnection
                connection.connectTimeout = 30000
                connection.readTimeout = 60000
                
                // Поддержка возобновления загрузки
                if (downloadedSoFar > 0) {
                    connection.setRequestProperty("Range", "bytes=$downloadedSoFar-")
                    Log.d(TAG, "Resuming download from $downloadedSoFar bytes (attempt $attempt)")
                } else {
                    Log.d(TAG, "Starting download (attempt $attempt)")
                }
                
                connection.connect()
                
                val responseCode = connection.responseCode
                val isResume = responseCode == 206
                // Берём размер с сервера - он всегда актуальный
                val totalSize = if (isResume) {
                    downloadedSoFar + connection.contentLengthLong
                } else {
                    connection.contentLengthLong
                }
                
                connection.inputStream.use { input ->
                    FileOutputStream(tempFile, isResume).use { output ->
                        val buffer = ByteArray(8192)
                        var downloaded = downloadedSoFar
                        var bytesRead: Int
                        var lastNotifyTime = System.currentTimeMillis()
                        
                        while (input.read(buffer).also { bytesRead = it } != -1) {
                            if (!downloadJob!!.isActive) throw CancellationException()
                            
                            output.write(buffer, 0, bytesRead)
                            downloaded += bytesRead
                            
                            val now = System.currentTimeMillis()
                            if (now - lastNotifyTime > 500) {
                                val progress = if (totalSize > 0) (downloaded.toDouble() / totalSize).coerceAtMost(1.0) else 0.0
                                currentProgress = progress
                                
                                withContext(Dispatchers.Main) {
                                    updateNotification(modelName, (progress * 100).toInt())
                                    notifyProgress(modelId, progress, "downloading")
                                }
                                lastNotifyTime = now
                            }
                        }
                    }
                }
                
                // Успешно загружено
                tempFile.renameTo(outputFile)
                
                withContext(Dispatchers.Main) {
                    updateNotification(modelName, 100)
                    notifyProgress(modelId, 1.0, "completed")
                }
                
                Log.d(TAG, "Download completed: ${outputFile.absolutePath}")
                return // Выход из функции при успехе
                
            } catch (e: CancellationException) {
                throw e // Не retry при отмене
            } catch (e: Exception) {
                lastException = e
                Log.w(TAG, "Download attempt $attempt failed: ${e.message}")
                
                if (attempt < maxRetries) {
                    // Ждём перед повторной попыткой
                    delay(2000L * attempt)
                }
            } finally {
                connection?.disconnect()
            }
        }
        
        // Все попытки исчерпаны
        throw lastException ?: Exception("Download failed after $maxRetries attempts")
    }
    
    private fun cancelDownload() {
        downloadJob?.cancel()
        isDownloading = false
        
        // Delete temp file
        currentModelId?.let { modelId ->
            val tempFile = File(File(filesDir, "models"), "$modelId.gguf.tmp")
            if (tempFile.exists()) tempFile.delete()
        }
        
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }
    
    private fun createNotification(modelName: String, progress: Int): android.app.Notification {
        val cancelIntent = Intent(this, DownloadService::class.java).apply {
            action = ACTION_CANCEL
        }
        val cancelPendingIntent = PendingIntent.getService(
            this, 0, cancelIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Загрузка: $modelName")
            .setContentText("$progress%")
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setProgress(100, progress, false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(android.R.drawable.ic_delete, "Отмена", cancelPendingIntent)
            .build()
    }
    
    private fun updateNotification(modelName: String, progress: Int) {
        val notification = createNotification(modelName, progress)
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, notification)
    }
    
    private fun notifyProgress(modelId: String, progress: Double, status: String) {
        progressCallback?.invoke(modelId, progress, status)
    }
    
    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
