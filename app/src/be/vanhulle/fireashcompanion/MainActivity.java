package be.vanhulle.fireashcompanion;

import android.app.Activity;
import android.app.ActivityOptions;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.hardware.display.DisplayManager;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.provider.Settings;
import android.view.Display;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;

public class MainActivity extends Activity {
    static final String HOST = "app.local";
    static final String DEFAULT_GAME_DIR = "/storage/emulated/0/JoiPlay/Pokemon Fire Ash 3.7";
    static final String EXTRA_MOVED = "moved";

    WebView web;
    SharedPreferences prefs;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        prefs = getSharedPreferences("cfg", MODE_PRIVATE);

        // Started on the main (top) screen? Move ourselves to the bottom screen.
        if (!getIntent().getBooleanExtra(EXTRA_MOVED, false) && moveToSecondaryDisplay()) {
            finish();
            return;
        }

        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        web = new WebView(this);
        setContentView(web);
        hideSystemBars();

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setCacheMode(WebSettings.LOAD_NO_CACHE);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        web.setBackgroundColor(0xFF15131F);
        web.addJavascriptInterface(new Bridge(), "Native");
        web.setWebChromeClient(new android.webkit.WebChromeClient());   // enables confirm()/alert() dialogs
        web.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest req) {
                Uri u = req.getUrl();
                if (!HOST.equals(u.getHost())) return null;
                return serve(u.getPath());
            }
        });

        if (!Environment.isExternalStorageManager()) {
            try {
                Intent i = new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                        Uri.parse("package:" + getPackageName()));
                startActivity(i);
            } catch (Exception ignored) { }
        }
        web.loadUrl("https://" + HOST + "/app/index.html");
    }

    boolean moveToSecondaryDisplay() {
        try {
            Display current = getDisplay();
            DisplayManager dm = (DisplayManager) getSystemService(Context.DISPLAY_SERVICE);
            Display target = null;
            for (Display d : dm.getDisplays()) {
                if (d.getDisplayId() != Display.DEFAULT_DISPLAY && (d.getFlags() & Display.FLAG_PRESENTATION) != 0) {
                    target = d;
                    break;
                }
            }
            if (target == null || current == null || current.getDisplayId() == target.getDisplayId()) return false;
            Intent i = new Intent(this, MainActivity.class);
            i.putExtra(EXTRA_MOVED, true);
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_MULTIPLE_TASK);
            ActivityOptions o = ActivityOptions.makeBasic();
            o.setLaunchDisplayId(target.getDisplayId());
            startActivity(i, o.toBundle());
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    void hideSystemBars() {
        try {
            WindowInsetsController c = getWindow().getInsetsController();
            if (c != null) {
                c.hide(WindowInsets.Type.statusBars() | WindowInsets.Type.navigationBars());
                c.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
            }
        } catch (Exception ignored) { }
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) hideSystemBars();
    }

    String gameDir() {
        return prefs.getString("gameDir", DEFAULT_GAME_DIR);
    }

    static final Map<String, String> MIME = new HashMap<>();
    static {
        MIME.put("html", "text/html");
        MIME.put("js", "application/javascript");
        MIME.put("css", "text/css");
        MIME.put("json", "application/json");
        MIME.put("png", "image/png");
        MIME.put("svg", "image/svg+xml");
        MIME.put("woff2", "font/woff2");
        MIME.put("ttf", "font/ttf");
    }

    static String mimeOf(String name) {
        int dot = name.lastIndexOf('.');
        String ext = dot >= 0 ? name.substring(dot + 1).toLowerCase() : "";
        String m = MIME.get(ext);
        return m != null ? m : "application/octet-stream";
    }

    WebResourceResponse serve(String path) {
        try {
            if (path == null) return notFound();
            if (path.startsWith("/app/")) {
                String rel = path.substring(5);
                InputStream in = getAssets().open("www/" + rel);
                return ok(mimeOf(rel), in);
            }
            if (path.startsWith("/game/")) {
                String rel = path.substring(6);
                if (rel.contains("..")) return notFound();
                File f = new File(gameDir(), rel);
                if (!f.isFile()) {
                    for (String ext : new String[]{".png", ".PNG"}) {
                        File g = new File(gameDir(), rel + ext);
                        if (g.isFile()) { f = g; break; }
                    }
                }
                if (!f.isFile()) return notFound();
                return ok(mimeOf(f.getName()), new FileInputStream(f));
            }
        } catch (Exception e) {
            return notFound();
        }
        return notFound();
    }

    WebResourceResponse ok(String mime, InputStream in) {
        WebResourceResponse r = new WebResourceResponse(mime, "utf-8", in);
        Map<String, String> h = new HashMap<>();
        h.put("Cache-Control", mime.startsWith("image/") ? "max-age=3600" : "no-store");
        h.put("Access-Control-Allow-Origin", "*");
        r.setResponseHeaders(h);
        return r;
    }

    WebResourceResponse notFound() {
        WebResourceResponse r = new WebResourceResponse("text/plain", "utf-8", new ByteArrayInputStream(new byte[0]));
        r.setStatusCodeAndReasonPhrase(404, "Not Found");
        return r;
    }

    class Bridge {
        @JavascriptInterface
        public String getGameDir() { return gameDir(); }

        @JavascriptInterface
        public void setGameDir(String dir) { prefs.edit().putString("gameDir", dir).apply(); }

        @JavascriptInterface
        public boolean hasStorageAccess() { return Environment.isExternalStorageManager(); }

        /** Queue commands for the game: merges with a pending cmd.json that was not picked up yet. */
        @JavascriptInterface
        public synchronized boolean sendCommands(String jsonArray) {
            try {
                File dir = new File(gameDir(), "DualScreen");
                dir.mkdirs();
                File f = new File(dir, "cmd.json");
                String body = jsonArray.trim();
                if (f.isFile()) {
                    String old = new String(java.nio.file.Files.readAllBytes(f.toPath()), "UTF-8").trim();
                    if (old.startsWith("[") && old.endsWith("]") && old.length() > 2 && body.startsWith("[") && body.length() > 2) {
                        body = old.substring(0, old.length() - 1) + "," + body.substring(1);
                    }
                }
                File tmp = new File(dir, "cmd.json.part");
                java.nio.file.Files.write(tmp.toPath(), body.getBytes("UTF-8"));
                if (!tmp.renameTo(f)) {
                    java.nio.file.Files.write(f.toPath(), body.getBytes("UTF-8"));
                    tmp.delete();
                }
                return true;
            } catch (Exception e) {
                return false;
            }
        }

        @JavascriptInterface
        public String listJoiPlayGames() {
            File root = new File("/storage/emulated/0/JoiPlay");
            StringBuilder sb = new StringBuilder();
            File[] kids = root.listFiles();
            if (kids != null) for (File k : kids) {
                if (k.isDirectory() && new File(k, "Game.ini").isFile()) {
                    if (sb.length() > 0) sb.append('\n');
                    sb.append(k.getAbsolutePath());
                }
            }
            return sb.toString();
        }
    }

    @Override
    protected void onDestroy() {
        if (web != null) web.destroy();
        super.onDestroy();
    }
}
