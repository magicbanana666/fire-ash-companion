package be.vanhulle.fireashcompanion;

import android.accessibilityservice.AccessibilityService;
import android.app.ActivityOptions;
import android.content.Context;
import android.content.Intent;
import android.hardware.display.DisplayManager;
import android.os.Handler;
import android.os.Looper;
import android.view.Display;
import android.view.accessibility.AccessibilityEvent;

import java.io.File;

/**
 * Watches for the JoiPlay RPG Maker runtime. When it starts and the Fire Ash
 * plugin writes DualScreen/boot.txt, the companion is opened on the bottom screen.
 */
public class GameWatcherService extends AccessibilityService {
    static final String RUNTIME_PKG = "cyou.joiplay.runtime.rpgmaker";
    static final long SESSION_GAP_MS = 60_000;     // runtime unseen this long = new session
    static final long BOOT_WAIT_MS = 45_000;       // how long to wait for boot.txt

    final Handler handler = new Handler(Looper.getMainLooper());
    long lastSeen = 0;
    long sessionStart = 0;
    boolean launchedThisSession = false;
    boolean polling = false;

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        if (event == null || event.getPackageName() == null) return;
        if (!RUNTIME_PKG.contentEquals(event.getPackageName())) return;
        long now = System.currentTimeMillis();
        if (now - lastSeen > SESSION_GAP_MS) {
            sessionStart = now;
            launchedThisSession = false;
        }
        lastSeen = now;
        if (!launchedThisSession && !polling) {
            polling = true;
            poll(sessionStart);
        }
    }

    void poll(final long start) {
        handler.postDelayed(() -> {
            long now = System.currentTimeMillis();
            File boot = new File(gameDir(), "DualScreen/boot.txt");
            if (boot.isFile() && boot.lastModified() >= start - 5_000) {
                launchedThisSession = true;
                polling = false;
                launchCompanion();
                return;
            }
            if (now - start > BOOT_WAIT_MS) { polling = false; return; }
            poll(start);
        }, 1500);
    }

    String gameDir() {
        return getSharedPreferences("cfg", Context.MODE_PRIVATE)
                .getString("gameDir", MainActivity.DEFAULT_GAME_DIR);
    }

    void launchCompanion() {
        try {
            DisplayManager dm = (DisplayManager) getSystemService(Context.DISPLAY_SERVICE);
            Display target = null;
            for (Display d : dm.getDisplays()) {
                if (d.getDisplayId() != Display.DEFAULT_DISPLAY && (d.getFlags() & Display.FLAG_PRESENTATION) != 0) { target = d; break; }
            }
            Intent i = new Intent(this, MainActivity.class);
            i.putExtra(MainActivity.EXTRA_MOVED, true);
            // NEW_TASK without MULTIPLE_TASK: an already open companion is brought forward instead of duplicated
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            ActivityOptions o = ActivityOptions.makeBasic();
            if (target != null) o.setLaunchDisplayId(target.getDisplayId());
            startActivity(i, o.toBundle());
        } catch (Exception ignored) { }
    }

    @Override
    public void onInterrupt() { }
}
