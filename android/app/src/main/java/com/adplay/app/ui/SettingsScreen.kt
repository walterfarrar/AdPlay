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
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
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
    onClose: (() -> Unit)? = null,
) {
    val ctx = LocalContext.current
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
                    "Email support with your Player ID to request deletion of your anonymous session and game data.",
                    color = BrandMuted,
                    fontSize = 13.sp,
                )
                TextButton(onClick = {
                    val mail = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:support@fullyversed.com")).apply {
                        putExtra(Intent.EXTRA_SUBJECT, "AdPlay account deletion")
                        putExtra(
                            Intent.EXTRA_TEXT,
                            "Please delete my AdPlay account.\n\nPlayer ID: ${ui.playerId}\n",
                        )
                    }
                    ctx.startActivity(mail)
                }) { Text("Request deletion", color = BrandAccent) }
            }
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
