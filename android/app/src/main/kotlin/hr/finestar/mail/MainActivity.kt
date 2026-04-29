package hr.finestar.mail

import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
  private companion object {
    private const val METHOD_CHANNEL = "hr.finestar.mail/share_intent"
    private const val EVENT_CHANNEL = "hr.finestar.mail/share_intent_events"
    private const val METHOD_GET_INITIAL_SHARED_FILES = "getInitialSharedFiles"

    private const val EXTRA_STREAM = Intent.EXTRA_STREAM
    private const val MIME_TYPE_FALLBACK = "application/octet-stream"
    private const val SHARED_DIR_NAME = "shared_attachments"
    private const val CLEANUP_MAX_AGE_MS = 7L * 24L * 60L * 60L * 1000L // 7 days
  }

  private var pendingSharedFiles: List<Map<String, Any?>> = emptyList()
  private var events: EventChannel.EventSink? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          METHOD_GET_INITIAL_SHARED_FILES -> {
            val initial = pendingSharedFiles
            pendingSharedFiles = emptyList()
            result.success(initial)
          }
          else -> result.notImplemented()
        }
      }

    EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
      .setStreamHandler(
        object : EventChannel.StreamHandler {
          override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            this@MainActivity.events = events
          }

          override fun onCancel(arguments: Any?) {
            this@MainActivity.events = null
          }
        },
      )
  }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    handleShareIntent(intent, emitIfPossible = false)
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    handleShareIntent(intent, emitIfPossible = true)
  }

  private fun handleShareIntent(intent: Intent?, emitIfPossible: Boolean) {
    if (intent == null) return

    val action = intent.action ?: return
    if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return

    cleanupOldSharedAttachments()

    val sharedFiles = try {
      when (action) {
        Intent.ACTION_SEND -> {
          val uri = intent.getParcelableExtra<Uri>(EXTRA_STREAM)
          if (uri == null) emptyList() else listOfNotNull(copyUriToCache(uri))
        }
        Intent.ACTION_SEND_MULTIPLE -> {
          val uris = intent.getParcelableArrayListExtra<Uri>(EXTRA_STREAM) ?: arrayListOf()
          uris.mapNotNull { copyUriToCache(it) }
        }
        else -> emptyList()
      }
    } catch (_: Throwable) {
      emptyList()
    }

    if (sharedFiles.isEmpty()) return

    // Cold start: queue for Flutter to retrieve once it boots.
    pendingSharedFiles = sharedFiles

    // Warm start: if Flutter is already listening, emit immediately.
    if (emitIfPossible) {
      events?.success(sharedFiles)
    }
  }

  private fun copyUriToCache(uri: Uri): Map<String, Any?>? {
    val sharedDir = File(cacheDir, SHARED_DIR_NAME)
    if (!sharedDir.exists()) {
      sharedDir.mkdirs()
    }

    val fileName = queryDisplayName(uri) ?: "attachment_${System.currentTimeMillis()}"
    val mimeType = contentResolver.getType(uri) ?: MIME_TYPE_FALLBACK

    val outFile = File(sharedDir, "${System.currentTimeMillis()}_${sanitizeFileName(fileName)}")
    contentResolver.openInputStream(uri)?.use { input ->
      FileOutputStream(outFile).use { output ->
        input.copyTo(output)
      }
    } ?: return null

    val sizeBytes = outFile.length()
    return mapOf(
      "path" to outFile.absolutePath,
      "name" to fileName,
      "mimeType" to mimeType,
      "sizeBytes" to sizeBytes,
    )
  }

  private fun queryDisplayName(uri: Uri): String? {
    var cursor: Cursor? = null
    return try {
      cursor = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
      if (cursor == null || !cursor.moveToFirst()) return null
      val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
      if (index < 0) null else cursor.getString(index)
    } catch (_: Throwable) {
      null
    } finally {
      cursor?.close()
    }
  }

  private fun sanitizeFileName(value: String): String {
    // Avoid path traversal and illegal characters.
    return value.replace(Regex("[\\\\/:*?\"<>|]"), "_").take(200)
  }

  private fun cleanupOldSharedAttachments() {
    val sharedDir = File(cacheDir, SHARED_DIR_NAME)
    if (!sharedDir.exists() || !sharedDir.isDirectory) return

    val cutoff = System.currentTimeMillis() - CLEANUP_MAX_AGE_MS
    sharedDir.listFiles()?.forEach { file ->
      val lastModified = file.lastModified()
      if (lastModified > 0 && lastModified < cutoff) {
        try {
          file.delete()
        } catch (_: Throwable) {
          // best-effort cleanup
        }
      }
    }
  }
}
