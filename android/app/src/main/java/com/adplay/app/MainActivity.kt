package com.adplay.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import com.adplay.app.data.BoostType
import com.adplay.app.notifications.GameReminderScheduler
import com.adplay.app.ui.AdPlayTheme
import com.adplay.app.ui.BrandBgTop
import com.adplay.app.ui.HomeScreen
import com.adplay.app.ui.RedeemScreen

class MainActivity : ComponentActivity() {
    private val vm: GameViewModel by viewModels()

    private val notificationPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { /* scheduled alerts only fire if granted */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        GameReminderScheduler.ensureChannel(this)
        maybeRequestNotificationPermission()

        setContent {
            AdPlayTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    val ui by vm.ui.collectAsState()
                    var showRedeem by remember { mutableStateOf(false) }

                    HomeScreen(
                        ui = ui,
                        onTap = { vm.tap() },
                        onLonger = { vm.watch(BoostType.DURATION) },
                        onFaster = { vm.watch(BoostType.SPEED) },
                        onStronger = { vm.watch(BoostType.TAP_STRENGTH) },
                        onRedeem = {
                            vm.clearError()
                            showRedeem = true
                        },
                        onDebugReset = { vm.debugReset() },
                        onToggleBypassAds = { vm.setBypassAds(!ui.bypassAds) },
                        onRetry = { vm.start() },
                    )

                    if (showRedeem) {
                        Dialog(
                            onDismissRequest = { showRedeem = false },
                            properties = DialogProperties(
                                usePlatformDefaultWidth = false,
                                decorFitsSystemWindows = false,
                            ),
                        ) {
                            Surface(
                                Modifier.fillMaxSize(),
                                color = BrandBgTop,
                            ) {
                                RedeemScreen(
                                    ui = ui,
                                    onLoadHistory = { vm.loadWithdrawals() },
                                    onSubmit = { amount, bolt, done ->
                                        vm.withdraw(amount, bolt, done)
                                    },
                                    onClose = { showRedeem = false },
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private fun maybeRequestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
}

