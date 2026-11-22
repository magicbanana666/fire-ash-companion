package be.vanhulle.fireashcompanion;

import android.app.Activity;
import android.app.ActivityOptions;
import android.content.Context;
import android.content.Intent;
import android.hardware.display.DisplayManager;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.provider.Settings;
import android.view.Display;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.view.inputmethod.InputMethodManager;
import android.webkit.WebView;

/**
 * Companion opened from the launcher. During play the watcher service shows the
 * same UI as an overlay instead (an overlay never steals the controller focus);
 * this activity is for browsing the companion on its own.
 */
public class MainActivity extends Activity {
    static final String DEFAULT_GAME_DIR = CompanionWeb.DEFAULT_GAME_DIR;
    static final String EXTRA_MOVED = "moved";

    WebView web;

    /** The instance currently shown (closed when the overlay takes over). */
    static volatile MainActivity current;

    static boolean isOpen() {
        MainActivity a = current;
        return a != null && !a.isFinishing() && !a.isDestroyed();
    }

    static void closeIfOpen() {
        MainActivity a = current;
        if (a != null) a.runOnUiThread(a::finishAndRemoveTask);
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // While the game runs, the overlay already shows the companion.
        if (GameWatcherService.overlayShown()) { finish(); return; }

        // Started on the main (top) screen? Move ourselves to the bottom screen.
        if (!getIntent().getBooleanExtra(EXTRA_MOVED, false) && moveToSecondaryDisplay()) {
            finish();
            return;
        }

        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        current = this;
        web = CompanionWeb.create(this, this::setFocusable);
        setContentView(web);
        hideSystemBars();

        if (!Environment.isExternalStorageManager()) {
            try {
                startActivity(new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                        Uri.parse("package:" + getPackageName())));
            } catch (Exception ignored) { }
        }
    }

    void setFocusable(boolean focusable) {
        runOnUiThread(() -> {
            if (!focusable || web == null) return;
            web.requestFocus();
            InputMethodManager imm = (InputMethodManager) getSystemService(Context.INPUT_METHOD_SERVICE);
            web.postDelayed(() -> { if (imm != null) imm.showSoftInput(web, 0); }, 150);
        });
    }

    boolean moveToSecondaryDisplay() {
        try {
            Display cur = getDisplay();
            DisplayManager dm = (DisplayManager) getSystemService(Context.DISPLAY_SERVICE);
            Display target = null;
            for (Display d : dm.getDisplays()) {
                if (d.getDisplayId() != Display.DEFAULT_DISPLAY && (d.getFlags() & Display.FLAG_PRESENTATION) != 0) {
                    target = d;
                    break;
                }
            }
            if (target == null || cur == null || cur.getDisplayId() == target.getDisplayId()) return false;
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

    @Override
    protected void onDestroy() {
        if (current == this) current = null;
        if (web != null) web.destroy();
        super.onDestroy();
    }
}
