package be.vanhulle.fireashcompanion;

import android.content.Context;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.Environment;
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

/**
 * The companion UI: a WebView that serves the bundled page (https://app.local/app/...)
 * and the game folder (https://app.local/game/...). Used both by MainActivity and by
 * the overlay window that GameWatcherService shows on the second screen.
 */
public final class CompanionWeb {
    public static final String HOST = "app.local";
    public static final String DEFAULT_GAME_DIR = "/storage/emulated/0/JoiPlay/Pokemon Fire Ash 3.7";

    /** Lets the page ask for keyboard focus while you type in a text field. */
    public interface Host { void setFocusable(boolean focusable); }

    private CompanionWeb() { }

    public static String gameDir(Context ctx) {
        return prefs(ctx).getString("gameDir", DEFAULT_GAME_DIR);
    }

    static SharedPreferences prefs(Context ctx) {
        return ctx.getSharedPreferences("cfg", Context.MODE_PRIVATE);
    }

    public static WebView create(Context ctx, Host host) {
        WebView web = new WebView(ctx);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setCacheMode(WebSettings.LOAD_NO_CACHE);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        web.setBackgroundColor(0xFF15131F);
        web.addJavascriptInterface(new Bridge(ctx, host), "Native");
        web.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest req) {
                Uri u = req.getUrl();
                if (!HOST.equals(u.getHost())) return null;
                return serve(ctx, u.getPath());
            }
        });
        web.loadUrl("https://" + HOST + "/app/index.html");
        return web;
    }

    static final Map<String, String> MIME = new HashMap<>();
    static {
        MIME.put("html", "text/html");
        MIME.put("js", "application/javascript");
        MIME.put("css", "text/css");
        MIME.put("json", "application/json");
        MIME.put("png", "image/png");
        MIME.put("svg", "image/svg+xml");
        MIME.put("txt", "text/plain");
        MIME.put("woff2", "font/woff2");
        MIME.put("ttf", "font/ttf");
    }

    static String mimeOf(String name) {
        int dot = name.lastIndexOf('.');
        String ext = dot >= 0 ? name.substring(dot + 1).toLowerCase() : "";
        String m = MIME.get(ext);
        return m != null ? m : "application/octet-stream";
    }

    static WebResourceResponse serve(Context ctx, String path) {
        try {
            if (path == null) return notFound();
            if (path.startsWith("/app/")) {
                String rel = path.substring(5);
                InputStream in = ctx.getAssets().open("www/" + rel);
                return ok(mimeOf(rel), in);
            }
            if (path.startsWith("/game/")) {
                String rel = path.substring(6);
                if (rel.contains("..")) return notFound();
                String dir = gameDir(ctx);
                File f = new File(dir, rel);
                if (!f.isFile()) {
                    for (String ext : new String[]{".png", ".PNG"}) {
                        File g = new File(dir, rel + ext);
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

    static WebResourceResponse ok(String mime, InputStream in) {
        WebResourceResponse r = new WebResourceResponse(mime, "utf-8", in);
        Map<String, String> h = new HashMap<>();
        h.put("Cache-Control", mime.startsWith("image/") ? "max-age=3600" : "no-store");
        h.put("Access-Control-Allow-Origin", "*");
        r.setResponseHeaders(h);
        return r;
    }

    static WebResourceResponse notFound() {
        WebResourceResponse r = new WebResourceResponse("text/plain", "utf-8", new ByteArrayInputStream(new byte[0]));
        r.setStatusCodeAndReasonPhrase(404, "Not Found");
        return r;
    }

    static final class Bridge {
        final Context ctx;
        final Host host;

        Bridge(Context ctx, Host host) { this.ctx = ctx; this.host = host; }

        @JavascriptInterface
        public String getGameDir() { return gameDir(ctx); }

        @JavascriptInterface
        public void setGameDir(String dir) { prefs(ctx).edit().putString("gameDir", dir).apply(); }

        @JavascriptInterface
        public boolean hasStorageAccess() { return Environment.isExternalStorageManager(); }

        @JavascriptInterface
        public void setFocusable(boolean focusable) { if (host != null) host.setFocusable(focusable); }

        /** Queue commands for the game: merges with a pending cmd.json that was not picked up yet. */
        @JavascriptInterface
        public boolean sendCommands(String jsonArray) {
            synchronized (CompanionWeb.class) {
                try {
                    File dir = new File(gameDir(ctx), "DualScreen");
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
}
