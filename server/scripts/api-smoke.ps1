$base = "http://127.0.0.1:8787"
Write-Host "Health:" (Invoke-RestMethod "$base/health" | ConvertTo-Json -Compress)
$session = Invoke-RestMethod -Method Post -Uri "$base/auth/session" -ContentType "application/json" -Body '{"deviceId":"smoke-ps1"}'
$token = $session.token
$h = @{ Authorization = "Bearer $token" }
$state = Invoke-RestMethod -Uri "$base/game/state" -Headers $h
Write-Host "Balance:" $state.state.satsBalance "progress:" $state.state.progress
$tap = Invoke-RestMethod -Method Post -Uri "$base/game/tap" -Headers $h -ContentType "application/json" -Body "{}"
Write-Host "After tap progress:" $tap.state.progress
$boost = Invoke-RestMethod -Method Post -Uri "$base/ads/mock/complete" -Headers $h -ContentType "application/json" -Body '{"boostType":"duration"}'
Write-Host "Auto-fill:" $boost.state.autoFillActive "until" $boost.state.autoFillUntil
Write-Host "OK"
