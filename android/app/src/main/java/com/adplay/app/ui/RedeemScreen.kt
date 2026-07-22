package com.adplay.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.adplay.app.UiState

private val Panel = Color(0xFF171826)
private val PanelBorder = Color(0xFF2B2D3D)
private val FieldBg = Color(0xFF0B0C14)

@Composable
fun RedeemScreen(
    ui: UiState,
    onLoadHistory: () -> Unit,
    onSubmit: (amount: Int, bolt11: String, done: (Boolean) -> Unit) -> Unit,
    onClose: () -> Unit,
) {
    var amountText by remember { mutableStateOf("") }
    var invoice by remember { mutableStateOf("") }
    var submitted by remember { mutableStateOf(false) }
    var localError by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) { onLoadHistory() }

    Box(
        Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(listOf(BrandBgTop, BrandBgMid, BrandBgBottom)),
            )
            .statusBarsPadding()
            .navigationBarsPadding(),
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 12.dp),
        ) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Redeem", fontSize = 28.sp, fontWeight = FontWeight.Bold, color = BrandInk)
                TextButton(onClick = onClose) {
                    Text("Close", color = BrandMuted, fontWeight = FontWeight.SemiBold)
                }
            }

            Spacer(Modifier.height(12.dp))

            Column(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(Panel)
                    .border(1.dp, PanelBorder, RoundedCornerShape(16.dp))
                    .padding(16.dp),
            ) {
                Text(
                    "${ui.state.satsBalance} sats",
                    fontSize = 32.sp,
                    fontWeight = FontWeight.Bold,
                    color = BrandInk,
                )
                Text(
                    "Available balance",
                    color = BrandMuted,
                    fontSize = 13.sp,
                )
                Spacer(Modifier.height(10.dp))
                Text(
                    "Minimum withdrawal: ${ui.state.minWithdrawSats} sats",
                    color = BrandInk,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                )
                Spacer(Modifier.height(8.dp))
                Text(
                    "Paste a Lightning invoice. An admin pays it manually from a Lightning wallet.",
                    color = BrandMuted,
                    fontSize = 13.sp,
                    lineHeight = 18.sp,
                )
            }

            Spacer(Modifier.height(16.dp))

            Column(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(Panel)
                    .border(1.dp, PanelBorder, RoundedCornerShape(16.dp))
                    .padding(16.dp),
            ) {
                Text("Request", fontWeight = FontWeight.SemiBold, fontSize = 16.sp, color = BrandInk)
                Spacer(Modifier.height(12.dp))

                OutlinedTextField(
                    value = amountText,
                    onValueChange = { amountText = it.filter { ch -> ch.isDigit() } },
                    label = { Text("Amount (sats)") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    colors = redeemFieldColors(),
                )
                Spacer(Modifier.height(10.dp))
                OutlinedTextField(
                    value = invoice,
                    onValueChange = { invoice = it },
                    label = { Text("BOLT11 invoice") },
                    modifier = Modifier.fillMaxWidth(),
                    minLines = 3,
                    colors = redeemFieldColors(),
                )
                Spacer(Modifier.height(14.dp))
                Button(
                    onClick = {
                        localError = null
                        val amount = amountText.toIntOrNull()
                        if (amount == null) {
                            localError = "Enter a valid amount"
                            return@Button
                        }
                        onSubmit(amount, invoice.trim()) { ok ->
                            if (ok) {
                                submitted = true
                                amountText = ""
                                invoice = ""
                            }
                        }
                    },
                    enabled = amountText.isNotBlank() && invoice.isNotBlank(),
                    modifier = Modifier.fillMaxWidth().height(48.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = BrandAccent,
                        contentColor = BrandOnAccent,
                        disabledContainerColor = BrandInk.copy(alpha = 0.10f),
                        disabledContentColor = BrandMuted,
                    ),
                    shape = RoundedCornerShape(12.dp),
                ) {
                    Text("Submit withdrawal", fontWeight = FontWeight.Bold)
                }

                (localError ?: ui.error)?.let {
                    Spacer(Modifier.height(10.dp))
                    Text(it, color = Color(0xFFFF6B6B), fontSize = 13.sp)
                }

                if (submitted) {
                    Spacer(Modifier.height(10.dp))
                    Text(
                        "Request queued. Status updates after the Lightning payment is marked paid.",
                        color = BrandMuted,
                        fontSize = 13.sp,
                    )
                }
            }

            Spacer(Modifier.height(16.dp))

            Column(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(Panel)
                    .border(1.dp, PanelBorder, RoundedCornerShape(16.dp))
                    .padding(16.dp),
            ) {
                Text("History", fontWeight = FontWeight.SemiBold, fontSize = 16.sp, color = BrandInk)
                Spacer(Modifier.height(10.dp))
                if (ui.withdrawals.isEmpty()) {
                    Text("No withdrawals yet", color = BrandMuted, fontSize = 14.sp)
                } else {
                    ui.withdrawals.forEachIndexed { index, w ->
                        if (index > 0) Spacer(Modifier.height(10.dp))
                        Column(
                            Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(10.dp))
                                .background(FieldBg)
                                .border(1.dp, PanelBorder.copy(alpha = 0.7f), RoundedCornerShape(10.dp))
                                .padding(12.dp),
                        ) {
                            Text(
                                "${w.sats} sats · ${w.status}",
                                fontWeight = FontWeight.SemiBold,
                                color = BrandInk,
                            )
                            w.created_at?.let {
                                Text(it, color = BrandMuted, fontSize = 12.sp)
                            }
                        }
                    }
                }
            }

            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun redeemFieldColors() = OutlinedTextFieldDefaults.colors(
    focusedTextColor = BrandInk,
    unfocusedTextColor = BrandInk,
    focusedContainerColor = FieldBg,
    unfocusedContainerColor = FieldBg,
    disabledContainerColor = FieldBg,
    focusedBorderColor = BrandAccent,
    unfocusedBorderColor = PanelBorder,
    focusedLabelColor = BrandMuted,
    unfocusedLabelColor = BrandMuted,
    cursorColor = BrandAccent,
)
