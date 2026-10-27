# Zapbar flows

Approved behavior for this PR. **Needs real TV** or **Needs Jim's Mac** cannot be proved in the test suite. Everything else is covered by a fake transport or a pure check.

No dead end. Each action shows one calm line (installed, or why it failed) and a next step. Empty screens say what to do. A failed switch comes back usable. Text the user typed stays in the field until the TV accepts it.

## Not connected

Blocks send text, file, screenshot, and power steps that need the debugging link.

No address: "No TV address yet" → **Set up a new TV**. adb missing: Homebrew hint, or "Reinstall Zapbar" in the sandbox → **Check connection**. Helper failed: quit and reopen. Wrong address or debugging off: "The TV refused the connection… check the address." Unreachable: on, same network, debugging on → **Retry**. Not allowed yet: accept the prompt on the TV; Zapbar retries about 12 seconds. Offline or booting: "may be asleep or still booting" → **Retry** or **Turn on**. Mid-send silence: "The TV stopped answering" → do it again. No saved TV: setup only. Saved TV that does not answer: remote greyed out, **Retry**, **Turn on with Wake-on-LAN**. Wrong IP versus asleep needs a real TV.

## 1. Send text

There is no "Paste a link" box and no open-link command. One field, "Type, Return sends", sends whatever was typed or pasted, including a URL, as plain text. Zapbar does not check that it is a web link.

Paste works from the Mac: a standard Edit menu (Cut, Copy, Paste, Select All, Command-X/C/V/A) even though Zapbar lives in the menu bar; opening the panel activates the app and focuses the field; right-click Paste uses that same menu. A dropped string or URL is added to the field, after a space or a new line when the field already has text. An .apk dropped on the field is an install, not text. Command-V reaches the field: keyboard-as-remote passes Command-modified keys through, and it passes every key while the field is focused. Command-V on Jim's Mac needs his Mac. The menu list, the pass-through rule, and the "no URL check" rule are tested here.

An empty send says "Type something to send." for a few seconds. Zapbar sends only when the TV keyboard is actually shown (`mInputShown=true`). A served view with the keyboard hidden, including Netflix, is not ready, and a nested `mServedView=null` is not ready. The line is "No text field is focused on the TV. Open a search or text box on the TV, then press Retry." The text stays in the field. **Retry** shows for every failed send. When the TV is not connected, **Open Settings** and **Set up a new TV** sit beside Retry. The same check runs before a Sony send when a debugging connection can see the keyboard. A Sony-only TV cannot see the keyboard; if Sony refuses the text, the same line and Retry are the next step. Needs a real TV to prove a focused search box really receives the characters.

## 2. Install an app

Zapbar installs .apk files only. There is no send-to-Downloads and no image, video, or audio send. Drop an .apk on the panel or the menu-bar icon, or press **Choose .apk…** (the picker only offers .apk files). While it runs the line says "Installing …" with a spinner. **Cancel** stops it. Success: "Installed." Failure names the cause (newer version already there, file does not match, no space, needs a newer system, not built for this TV, blocked, cancelled, not a real app, missing library, or "The install didn't finish.") and a next step, usually choose the .apk again. A TV that is not on a debugging connection says "Reconnect the TV, then choose the .apk again." Any other install error, including the TV stopping mid-send or a missing helper, says "Check the TV and the network, then choose the .apk again." A file that is not an .apk, dropped or picked, says "Only .apk files can be installed. Choose an .apk…" and the picker button stays there. A drop that mixes an .apk with other files installs the .apk and adds "Skipped N file(s) that aren't .apk." **Show log** opens the install text (one entry per file: the sentence, the next step, and the raw output). A new install or a screenshot clears that log. **Copy** copies that text, and the text can be selected. The button works again when the install ends. A real install needs the TV. The wording and the log are tested here.

## 3. Screenshot

**Screenshot** shows "Taking a screenshot…", then a preview and "Screenshot ready." A black protected frame still shows, with the protected-video line. Failure: "didn't come back" or needs a debugging connection. **Copy** says "Copied." and stays off until there is a picture. Copy and the preview are unchanged. A real capture needs the TV.

**Save…** sits beside Copy. The app may already write files the user picks in the save dialog. The dialog starts in Desktop when that folder URL exists, otherwise Pictures. Default name "Zapbar Screenshot YYYY-MM-DD at HH.mm.ss.png", PNG. Lines: "Saved" and "Couldn't save". No sound. The name is tested here. Whether the dialog opens on Desktop inside the sandbox needs a Mac.

## 4. Power

The panel does not treat open debugging ports as on. If adb is connected, the TV's own wake line wins: Awake = on, Asleep or Dozing = off. If that line is missing and a Sony key is saved, Sony active = on and standby = off. If neither answers, the state is unknown. Unknown is never shown as on.

Asleep or unknown: **Turn on**. Awake: **Turn off** (a second click still confirms). Turn on tries the adb wake key, then Sony power-on if a key is saved, then a magic packet. The MAC is learned from the neighbour table, the TV's network address, or saved on that TV. The packet goes to ports 9 and 7 on the subnet broadcast. Turn off tries the sleep key, then Sony power-off. After a press, Zapbar looks for about 6 seconds. If nothing changed, it tries the next method once. If it still did not change, the line is "TV didn't respond — try again" and the button works again. It does not stay disabled or mislabeled. While the panel is open, power is rechecked every 3–5 seconds, and again right after a press. The ladder and the asleep-but-connected case are tested with a stand-in. Jim's asleep Sony, the wake key, and a real magic packet need his TV.

## 5. Launch at login

Settings has one switch, "Launch at login", matching macOS. On only when macOS says it is enabled. If approval is required, the switch stays off, the line says macOS needs approval, and **Open Login Items** opens System Settings. If the login item is missing, the switch stays off and says to turn it on again. Off removes it. After every press the switch shows the real status again. The four status words are tested here. The real system switch needs Jim's Mac.
