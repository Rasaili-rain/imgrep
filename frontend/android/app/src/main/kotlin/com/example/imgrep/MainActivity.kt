package com.example.imgrep

import java.io.File
import android.content.Context
import android.content.ContentUris
import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity: FlutterActivity() {
  private val GHALLERY_HOOK_CHANNEL = "GALLERY_HOOK_CHANNEL"
  private var observer: ContentObserver? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    // Creating a new "gallary_changes" channel
    EventChannel(flutterEngine.dartExecutor.binaryMessenger, GHALLERY_HOOK_CHANNEL)
      .setStreamHandler(object : EventChannel.StreamHandler {

        // This is for flutter to listen to event channel
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {

          // Creating a Media Change Hook
          observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
              // There is something wrong if the uri is null
              if (uri == null) {
                events?.success(mapOf(
                  "type" to "UNKNOWN",
                  "note" to "uri was null"
                ))
                return
              }

              val id = ContentUris.parseId(uri) // Extracting ID from URI
              val cursor = contentResolver.query(uri, null, null, null, null)

              // If the cursor is null it means the media is deleted
              if (cursor == null || !cursor.moveToFirst()) {
                events?.success(mapOf(
                  "type" to "DELETE",
                  "id" to id.toString()
                ))
                return
              }

              // Getting the file path
              val path = cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATA))

              // Checking if the file is in the trashbin
              val isTrashedIndex = cursor.getColumnIndex(MediaStore.MediaColumns.IS_TRASHED)
              val isTrashed = if (isTrashedIndex != -1) cursor.getInt(isTrashedIndex) == 1 else false

              if (isTrashed || !File(path).exists()) {
                events?.success(mapOf(
                  "type" to "DELETE",
                  "id" to id.toString()
                ))
              } else {
                events?.success(mapOf(
                  "type" to "UPDATE",
                  "id" to id.toString()
                ))
              }

              cursor.close()
            }
          }

          // Registering the observer for the photo events
          contentResolver.registerContentObserver(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            true,
            observer!!
          )
        }

        // This is for flutter to close the event channel
        override fun onCancel(arguments: Any?) {
          if (observer != null) {
            contentResolver.unregisterContentObserver(observer!!)
            observer = null
          }
        }

      })
  }
}
