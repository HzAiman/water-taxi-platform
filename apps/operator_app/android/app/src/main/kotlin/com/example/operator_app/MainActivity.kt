package com.example.operator_app

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val mapsChannel = "operator_app/maps_config"
	private val screenAwakeChannel = "operator_app/screen_awake"
	private val phoneChannel = "operator_app/phone"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mapsChannel)
			.setMethodCallHandler { call, result ->
				if (call.method != "getMapsConfigStatus") {
					result.notImplemented()
					return@setMethodCallHandler
				}

				try {
					val appInfo = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
					val mapsKey = appInfo.metaData?.getString("com.google.android.geo.API_KEY")?.trim() ?: ""
					val hasPlaceholder = mapsKey.contains("\${MAPS_API_KEY}") || mapsKey == "MAPS_API_KEY"
					val injected = mapsKey.isNotEmpty() && !hasPlaceholder
					val preview = if (injected && mapsKey.length > 6) {
						"${mapsKey.take(4)}...${mapsKey.takeLast(2)}"
					} else {
						""
					}

					result.success(
						mapOf(
							"injected" to injected,
							"placeholder" to hasPlaceholder,
							"length" to mapsKey.length,
							"preview" to preview,
						),
					)
				} catch (e: Exception) {
					result.success(
						mapOf(
							"injected" to false,
							"error" to (e.message ?: "Unable to read manifest meta-data"),
						),
					)
				}
			}

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, screenAwakeChannel)
			.setMethodCallHandler { call, result ->
				if (call.method != "setKeepScreenOn") {
					result.notImplemented()
					return@setMethodCallHandler
				}

				val enabled = call.argument<Boolean>("enabled") ?: false
				runOnUiThread {
					if (enabled) {
						window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
					} else {
						window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
					}
					result.success(null)
				}
			}

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, phoneChannel)
			.setMethodCallHandler { call, result ->
				if (call.method != "dial") {
					result.notImplemented()
					return@setMethodCallHandler
				}

				val phone = call.argument<String>("phone")?.trim().orEmpty()
				if (phone.isEmpty()) {
					result.success(false)
					return@setMethodCallHandler
				}

				try {
					val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$phone"))
					startActivity(intent)
					result.success(true)
				} catch (e: Exception) {
					result.success(false)
				}
			}
	}
}
