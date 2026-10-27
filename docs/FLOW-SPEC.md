# Zapbar flows

Read from current main: the 1.1.0 app (tag ffe2dba) plus later README-only commits. **Exists today** is already in the app. **New in this PR** is not built; we build it only after this page is approved. **Needs real TV** cannot be proved here.

New work has no dead end. Each action shows one calm line (opened, installed, queued, or why it failed) and a next button. Empty screens say what to do. A failed switch comes back usable.

## Not connected (blocks link, file, screenshot, and adb power)

All of this exists today. No address: "No TV address yet" → **Set up a new TV**. adb missing: Homebrew hint, or "Reinstall Zapbar" in the sandbox → **Check connection**. Helper failed: quit and reopen. Wrong address or debugging off: "The TV refused the connection… check the address." Unreachable: on, same network, debugging on → **Retry**. Not allowed yet: accept the prompt on the TV; Zapbar retries about 12 seconds. Offline or booting: "may be asleep or still booting" → **Retry** or **Turn on**. Mid-send silence: "The TV stopped answering" → do it again. No saved TV: setup only. Saved TV that does not answer: remote greyed out, **Retry**, **Turn on with Wake-on-LAN**. Wrong IP versus asleep needs a real TV.

## 1. Link

One box matches the report: **Paste a link**, under the remote, above Screenshot. Return sends. Control-Option-L focuses it. Other boxes are not this: "Type, Return sends", and Settings address, ports, Sony key, and MAC.

Today, http/https is sent with the TV's open command. A browser, YouTube, or another app may take it. Zapbar does not choose. "Opened on the TV." Not a web link: "Only web links can be sent." Nothing handles it: "No app on the TV can open this." Other failure: "It needs a browser." The box is ready again. Which app opens needs a real TV.

Paste fails because a menu-bar app has no Edit menu, so Command-V goes nowhere. The panel can become key, but opening it does not activate the app, and the box takes no right-click Paste and no dropped link. **New:** Edit menu (Cut, Copy, Paste, Select All); activate the app and focus the box; accept a dropped link or text. Command-V, right-click Paste, and drag-in fill the box. Return still sends. Command-V needs Jim's Mac. The menu and drop can be checked here.

## 2. File

Drop on the panel or menu icon: .apk only, else "Drop an app file ending in .apk." Success: "Installed." Failures name the cause: newer version already there, does not match, no space, needs a newer system, not built for this TV, blocked, cancelled, not a real app, missing library, or "The install didn't finish." Drop again when the job ends. A real install needs the TV.

**Send file…** copies any readable file to TV Downloads and asks the TV to open it. Known: video mp4 m4v mkv webm mov avi; audio mp3 m4a aac; image jpg png gif webp; also pdf. Other types are still sent. Success does not say opened: "Sent. The TV needs a player." Nothing can open it: "No app on the TV can open this." Copied but not opened: "in Downloads" / "did not open." Copy failed: "didn't reach the TV." No space, folder refused, or unreadable each have their own line. No Mac size cap. **Cancel** removes a partial copy.

**New:** apk → "Installed." Image, video, audio → "Opened on the TV." or, if no player starts, "Queued in Downloads." Anything else is not sent, and the line lists accepted types: app (.apk), video (mp4, m4v, mov, mkv, webm, avi), audio (mp3, m4a, aac), image (jpg, png, gif, webp). Next button stays **Send file…**. A huge file the TV rejects uses the no-space line. Players and huge files need the TV.

## 3. Screenshot

**Screenshot** → "Taking a screenshot…", then a preview and "Screenshot ready." A black protected frame still shows, with the protected-video line. Failure: "didn't come back" or needs a debugging connection. **Copy** → "Copied." and stays off until there is a picture. A real capture needs the TV.

**Save…** already sits beside Copy. The save dialog is allowed to write files the user picks. Today: Downloads, "Zapbar screenshot.png" (or 2, 3), "Saved." / "The screenshot couldn't be saved."

**New:** Desktop if the dialog allows, else Pictures. Name "Zapbar Screenshot YYYY-MM-DD at HH.mm.ss.png", PNG. Lines: "Saved" and "Couldn't save". No sound. Copy and preview stay. The name can be tested here. Desktop in the sandbox needs a Mac.

## 4. Power

Today, open debugging ports count as on. Connected, with no Sony power answer: status "adb connected", and the only control is sleep (click, then click again to turn off). Unknown while connected is also on. Jim's Sony was asleep, ports were open, turn off did nothing, and he could not wake it. A real off shows **Wake**. Wake tries Sony on, then the adb wake key, then a magic packet only if Wake-on-LAN is on and a MAC is typed in (port 9). Sleep is the sleep key or Sony off. Recheck is about every 10 seconds, not after a press.

**New:** read the real state. adb wake line if connected (Awake = on; Asleep or Dozing = off). Else Sony if a key is saved (active / standby). Else unknown. Never call ports-open "on". Asleep: **Turn on** (wake key, then Sony on, then magic packet on ports 9 and 7). MAC is learned and saved on that TV. Awake: **Turn off**. After a press, look ~6 seconds; if unchanged, try the next method once; if still unchanged, "TV didn't respond — try again" and the button works again. Never stuck or mislabeled. While open, recheck every 3–5 seconds and right after a press. Unknown: **Turn on** and "No answer yet". The ladder can use stand-ins. Jim's asleep Sony, the wake key, and a real packet need his TV.

## 5. Launch at login

No switch today. **New:** one Settings switch matching macOS. On only when enabled. If approval is required, it does not pretend to be on; **Open Login Items** opens System Settings. If the item is missing, it stays off and says to turn it on again. Off removes it. It always shows the real status. The three macOS answers need a Mac; the wording can be tested here.
