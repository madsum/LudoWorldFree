package nl.iprosoft.ludo

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener

class MainActivity : FlutterActivity() {
    private val channelName = "nl.iprosoft.ludo/referral"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "getInstallReferrer") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val client = InstallReferrerClient.newBuilder(this).build()
                client.startConnection(object : InstallReferrerStateListener {
                    override fun onInstallReferrerSetupFinished(responseCode: Int) {
                        if (responseCode == InstallReferrerClient.InstallReferrerResponse.OK) {
                            try {
                                result.success(client.installReferrer.installReferrer)
                            } catch (_: Exception) {
                                result.success(null)
                            }
                        } else {
                            result.success(null)
                        }
                        client.endConnection()
                    }

                    override fun onInstallReferrerServiceDisconnected() {
                        Handler(Looper.getMainLooper()).post { result.success(null) }
                    }
                })
            }
    }
}
