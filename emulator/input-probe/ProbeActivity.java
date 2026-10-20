package app.pohstep.inputprobe;

import android.app.Activity;
import android.content.Context;
import android.graphics.Color;
import android.os.Bundle;
import android.text.Editable;
import android.text.InputType;
import android.text.TextWatcher;
import android.util.Log;
import android.view.KeyEvent;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.widget.EditText;

public class ProbeActivity extends Activity implements TextWatcher {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        ProbeField field = new ProbeField(this);
        field.setText("");
        field.setHint("probe");
        field.setTextColor(Color.WHITE);
        field.setSingleLine(true);
        field.setShowSoftInputOnFocus(false);
        field.setInputType(InputType.TYPE_CLASS_TEXT
                | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
                | InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD);
        field.addTextChangedListener(this);
        setContentView(field);
        field.requestFocus();
    }

    /** Hardware keys from `adb shell input text` should land here, not in the TV IME. */
    public static class ProbeField extends EditText {
        public ProbeField(Context context) {
            super(context);
        }

        @Override
        public boolean onCheckIsTextEditor() {
            return false;
        }

        @Override
        public InputConnection onCreateInputConnection(EditorInfo outAttrs) {
            return null;
        }
    }

    @Override
    public void beforeTextChanged(CharSequence s, int start, int count, int after) {}

    @Override
    public void onTextChanged(CharSequence s, int start, int before, int count) {}

    @Override
    public void afterTextChanged(Editable s) {
        Log.i("InputProbe", "TEXT=" + s.toString());
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        if (event.getAction() == KeyEvent.ACTION_DOWN) {
            Log.i("InputProbe", "KEY=" + event.getKeyCode());
        }
        return super.dispatchKeyEvent(event);
    }
}
