package be.vanhulle.fireashcompanion;

import android.accessibilityservice.AccessibilityService;
import android.content.Context;
import android.graphics.PixelFormat;
import android.graphics.Point;
import android.hardware.display.DisplayManager;
import android.os.Handler;
import android.os.Looper;
import android.view.Display;
import android.view.WindowManager;
import android.view.accessibility.AccessibilityEvent;
import android.view.inputmethod.InputMethodManager;
import android.webkit.WebView;

import java.io.File;

/**
 * Shows the companion on the second screen while Fire Ash is in front, and hides it
 * when you leave the game (quit, home button, other app). Coming back shows it again.
 *
 * The companion is shown as an accessibility overlay window instead of an activity:
 * starting an activity on the second screen makes that screen the "focused" one, so
 * the controller would stop working in the game until you tap the top screen. An
 * overlay never takes the focus, so the game keeps all controller input.
 *
 * Fire Ash is recognised by DualScreen/alive.txt, which the in-game plugin refreshes
 * every second. Only package/class names of window changes are used; no screen
 * content is read.
 */
public class GameWatcherService extends AccessibilityService {
    static final String RUNTIME_PKG = "cyou.joiplay.runtime.rpgmaker";
    static final long ALIVE_FRESH_MS = 4_000;
    static final long WAIT_FOR_GAME_MS = 90_000;
    static final long HIDE_DELAY_MS = 1_500;

    static volatile GameWatcherService instance;

    final Handler handler = new Handler(Looper.getMainLooper());
    boolean gameOnTop = false;
    long gameOnTopSince = 0;
    boolean polling = false;

    WebView overlay;
    WindowManager overlayWm;
    WindowManager.LayoutParams overlayLp;

    /**
     * After the device sleeps and wakes, the overlay could get the main screen's
     * size (1920 wide) instead of the second screen's, so the page was laid out too
     * wide and looked zoomed in / cut off. The overlay therefore gets the second
     * screen's exact size, re-checked on every display change (screen on/off,
     * rotation); if the view still has the wrong size it is rebuilt.
     */
    final DisplayManager.DisplayListener displayListener = new DisplayManager.DisplayListener() {
        @Override public void onDisplayAdded(int id) { }
        @Override public void onDisplayRemoved(int id) { scheduleSizeCheck(); }
        @Override public void onDisplayChanged(int id) { scheduleSizeCheck(); }
    };

    void scheduleSizeCheck() {
        handler.removeCallbacks(sizeCheck);
        handler.postDelayed(sizeCheck, 300);
    }

    static Point realSize(Display d) {
        Point p = new Point();
        d.getRealSize(p);
        return p;
    }

    final Runnable sizeCheck = () -> {
        if (overlay == null) return;
        Display d = secondDisplay();
        if (d == null) { hideOverlay(); return; }
        Point p = realSize(d);
        if (overlayLp.width != p.x || overlayLp.height != p.y) {
            overlayLp.width = p.x;
            overlayLp.height = p.y;
            try { overlayWm.updateViewLayout(overlay, overlayLp); } catch (Exception ignored) { }
        }
        handler.postDelayed(() -> {
            if (overlay == null) return;
            int w = overlay.getWidth(), h = overlay.getHeight();
            if (w > 0 && h > 0 && (w != p.x || h != p.y)) { hideOverlay(); showOverlay(); }
        }, 500);
    };

    static boolean overlayShown() {
        GameWatcherService s = instance;
        return s != null && s.overlay != null;
    }

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        instance = this;
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        if (event == null || event.getEventType() != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return;
        if (event.getDisplayId() != Display.DEFAULT_DISPLAY) return;          // only the main (top) screen
        CharSequence pkgCs = event.getPackageName();
        if (pkgCs == null) return;
        String pkg = pkgCs.toString();
        if (ignored(pkg, event.getClassName())) return;

        if (RUNTIME_PKG.equals(pkg)) {
            if (!gameOnTop) { gameOnTop = true; gameOnTopSince = System.currentTimeMillis(); }
            handler.removeCallbacks(hideCheck);
            startPolling();
        } else {
            gameOnTop = false;
            handler.removeCallbacks(hideCheck);
            handler.postDelayed(hideCheck, HIDE_DELAY_MS);
        }
    }

    /** Overlays, keyboards, system UI and our own windows never count as "something else on top". */
    boolean ignored(String pkg, CharSequence cls) {
        if (pkg.equals(getPackageName())) return true;
        if (pkg.equals("android") || pkg.startsWith("com.android.systemui")) return true;
        if (pkg.contains("inputmethod") || pkg.contains("keyboard")) return true;
        if (cls != null) {
            String c = cls.toString();
            if (c.contains("Dialog") || c.contains("Toast") || c.contains("PopupWindow") || c.startsWith("android.widget")) return true;
        }
        return false;
    }

    final Runnable hideCheck = () -> { if (!gameOnTop) hideOverlay(); };

    void startPolling() {
        if (polling) return;
        polling = true;
        handler.post(pollTask);
    }

    final Runnable pollTask = new Runnable() {
        @Override public void run() {
            if (!gameOnTop || overlay != null) { polling = false; return; }
            if (fireAshRunning()) { polling = false; showOverlay(); return; }
            if (System.currentTimeMillis() - gameOnTopSince > WAIT_FOR_GAME_MS) { polling = false; return; }
            handler.postDelayed(this, 1000);
        }
    };

    boolean fireAshRunning() {
        long now = System.currentTimeMillis();
        File dir = new File(CompanionWeb.gameDir(this), "DualScreen");
        File alive = new File(dir, "alive.txt");
        if (alive.isFile() && now - alive.lastModified() < ALIVE_FRESH_MS) return true;
        File boot = new File(dir, "boot.txt");   // written the moment the game's scripts load
        return boot.isFile() && boot.lastModified() >= gameOnTopSince - 5_000;
    }

    Display secondDisplay() {
        DisplayManager dm = (DisplayManager) getSystemService(Context.DISPLAY_SERVICE);
        for (Display d : dm.getDisplays()) {
            if (d.getDisplayId() != Display.DEFAULT_DISPLAY && (d.getFlags() & Display.FLAG_PRESENTATION) != 0) return d;
        }
        return null;
    }

    void showOverlay() {
        if (overlay != null) return;
        Display d = secondDisplay();
        if (d == null) return;   // single-screen device: never cover the game
        try {
            MainActivity.closeIfOpen();
            Context dc = createDisplayContext(d);
            overlayWm = (WindowManager) dc.getSystemService(Context.WINDOW_SERVICE);
            overlayLp = new WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                            | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                            | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
                            | WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED
                            | WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                    PixelFormat.OPAQUE);
            Point size = realSize(d);
            overlayLp.width = size.x;
            overlayLp.height = size.y;
            overlayLp.setTitle("Fire Ash Companion");
            overlay = CompanionWeb.create(dc, this::setOverlayFocusable);
            overlayWm.addView(overlay, overlayLp);
            ((DisplayManager) getSystemService(Context.DISPLAY_SERVICE)).registerDisplayListener(displayListener, handler);
        } catch (Exception e) {
            overlay = null;
        }
    }

    void hideOverlay() {
        if (overlay == null) return;
        handler.removeCallbacks(sizeCheck);
        try { ((DisplayManager) getSystemService(Context.DISPLAY_SERVICE)).unregisterDisplayListener(displayListener); } catch (Exception ignored) { }
        try { overlayWm.removeView(overlay); } catch (Exception ignored) { }
        try { overlay.destroy(); } catch (Exception ignored) { }
        overlay = null;
    }

    /** Text fields in the page: take focus (and the keyboard) only while typing. */
    void setOverlayFocusable(boolean focusable) {
        handler.post(() -> {
            if (overlay == null) return;
            InputMethodManager imm = (InputMethodManager) getSystemService(Context.INPUT_METHOD_SERVICE);
            if (focusable) {
                overlayLp.flags &= ~WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE;
                overlayWm.updateViewLayout(overlay, overlayLp);
                overlay.requestFocus();
                overlay.postDelayed(() -> { if (imm != null && overlay != null) imm.showSoftInput(overlay, 0); }, 150);
            } else {
                if (imm != null) imm.hideSoftInputFromWindow(overlay.getWindowToken(), 0);
                overlayLp.flags |= WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE;
                overlayWm.updateViewLayout(overlay, overlayLp);
            }
        });
    }

    @Override
    public void onInterrupt() { }

    @Override
    public void onDestroy() {
        hideOverlay();
        if (instance == this) instance = null;
        super.onDestroy();
    }
}
