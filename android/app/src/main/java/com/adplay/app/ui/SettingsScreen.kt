package com.adplay.app.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.adplay.app.UiState

@Composable
fun SettingsScreen(
    ui: UiState,
    onReminders: (Boolean) -> Unit,
    onHaptics: (Boolean) -> Unit,
    onSound: (Boolean) -> Unit,
    onDeleteAccount: ((done: (Boolean) -> Unit) -> Unit)? = null,
    onClose: (() -> Unit)? = null,
) {
    val ctx = LocalContext.current
    var confirmDelete by remember { mutableStateOf(false) }
    CenteredFitPage(Modifier.statusBarsPadding().navigationBarsPadding()) {
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Settings",
                    color = BrandInk,
                    fontSize = 28.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.weight(1f),
                )
                if (onClose != null) {
                    TextButton(onClick = onClose) {
                        Text("Close", color = BrandMuted, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
            Spacer(Modifier.height(16.dp))
            Panel("Play") {
                ToggleRow("Reminders", ui.remindersEnabled, onReminders)
                ToggleRow("Haptics", ui.hapticsEnabled, onHaptics)
                ToggleRow("Sound", ui.soundEnabled, onSound)
            }
            Spacer(Modifier.height(16.dp))
            Panel("Account") {
                Text("Player ID", color = BrandMuted, fontSize = 12.sp)
                Text(ui.playerId.ifBlank { "Not signed in" }, color = BrandInk, fontSize = 13.sp)
                Spacer(Modifier.height(8.dp))
                TextButton(onClick = {
                    ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://fullyversed.com/adplay/privacy")))
                }) { Text("Privacy policy", color = BrandAccent) }
                TextButton(onClick = {
                    ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://fullyversed.com/adplay/support")))
                }) { Text("Support", color = BrandAccent) }
            }
            Spacer(Modifier.height(16.dp))
            Panel("Delete account") {
                Text(
                    "Permanently erase this anonymous session and all game data on the server. This cannot be undone.",
                    color = BrandMuted,
                    fontSize = 13.sp,
                )
                TextButton(
                    onClick = { confirmDelete = true },
                    enabled = !ui.loading && onDeleteAccount != null,
                ) { Text("Delete my account", color = BrandPower) }
                if (!ui.error.isNullOrBlank()) {
                    Text(ui.error, color = BrandPower, fontSize = 13.sp)
                }
            }
    }
    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { if (!ui.loading) confirmDelete = false },
            containerColor = BrandCard,
            titleContentColor = BrandInk,
            textContentColor = BrandMuted,
            title = {
                Text("Delete account?", fontWeight = FontWeight.Bold, color = BrandInk)
            },
            text = {
                Text(
                    buildString {
                        append("This is permanent and cannot be undone. Your sats, play progress, combo, and any pending withdrawals will be erased. A new empty session will start on this device.")
                        if (!ui.error.isNullOrBlank()) {
                            append("\n\n")
                            append(ui.error)
                        }
                    },
                )
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = false }, enabled = !ui.loading) {
                    Text("Cancel", color = BrandMuted)
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        onDeleteAccount?.invoke { ok ->
                            if (ok) {
                                confirmDelete = false
                                onClose?.invoke()
                            }
                        }
                    },
                    enabled = !ui.loading,
                ) {
                    Text("Delete account", color = BrandPower, fontWeight = FontWeight.SemiBold)
                }
            },
        )
    }
}

@Composable
private fun ToggleRow(title: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, color = BrandInk, modifier = Modifier.weight(1f))
        Switch(
            checked = checked,
            onCheckedChange = onChange,
            colors = SwitchDefaults.colors(checkedThumbColor = BrandOnAccent, checkedTrackColor = BrandAccent),
        )
    }
}
