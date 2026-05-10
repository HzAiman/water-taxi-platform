package com.example.passenger_app

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
	private val phoneChannel = "passenger_app/phone"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

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
