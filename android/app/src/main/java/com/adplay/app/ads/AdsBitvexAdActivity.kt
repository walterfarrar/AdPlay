package com.adplay.app.ads

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.activity.ComponentActivity
import com.adplay.app.BuildConfig
import kotlinx.coroutines.CompletableDeferred

/**
 * Full-screen WebView host for AdsBitvex reward ads (JS SDK).
 * Resolves [pendingResult] when the ad Promise settles.
 */
class AdsBitvexAdActivity : ComponentActivity() {

    private var finished = false

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        val web = WebView(this).apply {
            setBackgroundColor(Color.BLACK)
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            settings.javaScriptCanOpenWindowsAutomatically = true
            settings.setSupportMultipleWindows(true)
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
            settings.cacheMode = WebSettings.LOAD_DEFAULT
            addJavascriptInterface(Bridge(), "AdPlayBridge")
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(
                    view: WebView,
                    request: WebResourceRequest,
                ): Boolean {
                    val url = request.url ?: return false
                    return openExternal(url)
                }
            }
            webChromeClient = object : WebChromeClient() {
                override fun onCreateWindow(
                    view: WebView?,
                    isDialog: Boolean,
                    isUserGesture: Boolean,
                    resultMsg: android.os.Message?,
                ): Boolean {
                    val transport = resultMsg?.obj as? WebView.WebViewTransport ?: return false
                    val child = WebView(this@AdsBitvexAdActivity).apply {
                        settings.javaScriptEnabled = true
                        webViewClient = object : WebViewClient() {
                            override fun shouldOverrideUrlLoading(
                                v: WebView,
                                request: WebResourceRequest,
                            ): Boolean {
                                openExternal(request.url)
                                return true
                            }
                        }
                    }
                    transport.webView = child
                    resultMsg.sendToTarget()
                    return true
                }
            }
        }
        root.addView(
            web,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        setContentView(root)
        web.loadDataWithBaseURL(
            "https://sdk.adsbitvex.com/",
            htmlPage(BuildConfig.ADSBITVEX_APP_ID),
            "text/html",
            "UTF-8",
            null,
        )
    }

    private fun openExternal(url: Uri?): Boolean {
        if (url == null || url.scheme.isNullOrBlank()) return false
        return try {
            startActivity(Intent(Intent.ACTION_VIEW, url))
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun finishWith(ok: Boolean) {
        if (finished) return
        finished = true
        pendingResult?.complete(ok)
        pendingResult = null
        setResult(if (ok) Activity.RESULT_OK else Activity.RESULT_CANCELED)
        finish()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        finishWith(false)
    }

    private inner class Bridge {
        @JavascriptInterface
        fun onAdResult(status: String, message: String) {
            runOnUiThread { finishWith(status == "ok") }
        }
    }

    companion object {
        @Volatile
        var pendingResult: CompletableDeferred<Boolean>? = null

        fun htmlPage(appId: String): String = """
            <!DOCTYPE html>
            <html>
            <head>
              <meta charset="utf-8"/>
              <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"/>
              <script src="https://sdk.adsbitvex.com/functions/v1/ad-script?appid=$appId"></script>
            </head>
            <body style="margin:0;background:#000;color:#ccc;font-family:sans-serif;
              display:flex;align-items:center;justify-content:center;height:100vh;text-align:center">
              <p id="status">Loading ad…</p>
              <script>
                function notify(ok, msg) {
                  try { AdPlayBridge.onAdResult(ok ? 'ok' : 'err', msg || ''); }
                  catch (e) {}
                }
                function run(tries) {
                  if (typeof window.showadsbitvex === 'function') {
                    document.getElementById('status').textContent = 'Watch to unlock boost…';
                    window.showadsbitvex()
                      .then(function () { notify(true, ''); })
                      .catch(function (e) {
                        notify(false, (e && e.message) ? e.message : String(e));
                      });
                    return;
                  }
                  if (tries > 50) {
                    document.getElementById('status').textContent = 'Ad SDK failed to load';
                    notify(false, 'SDK timeout');
                    return;
                  }
                  setTimeout(function () { run(tries + 1); }, 200);
                }
                run(0);
              </script>
            </body>
            </html>
        """.trimIndent()
    }
}
