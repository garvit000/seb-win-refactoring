# SEB for Windows — local development environment

A self-contained way to build and run **Safe Exam Browser for Windows** from PowerShell, Command Prompt, or Visual Studio in a relaxed, developer-friendly session, so the app can be debugged and UI-tested next to Visual Studio, VS Code, terminals, and normal browsers.

Everything belonging to this environment lives in this folder. No file outside `DevEnvironment/` is created or modified, and no SEB source code is changed.

> [!WARNING]
> **This is not an exam environment.** The configuration in this folder deliberately
> relaxes SEB's kiosk restrictions. It must never be used for an assessment, and it
> does not change how SEB behaves for anybody else.

---

## Quick start

### PowerShell:

```powershell
cd DevEnvironment

.\build-dev.ps1          # builds the Debug configuration into DevEnvironment\build
.\run-dev.ps1            # launches it with the development configuration
```

### Command Prompt / CMD:

```cmd
cd DevEnvironment

build-dev.cmd            # builds the Debug configuration into DevEnvironment\build
run-dev.cmd              # launches it with the development configuration
```

Quit the session with **Ctrl-Q**, **Alt-F4**, or the **Quit** button on the SEB taskbar.

Common variations:

```powershell
.\check-prereqs.ps1                         # checks if required SDKs and VS/MSBuild are present
.\run-dev.ps1 -Url http://localhost:3000     # point the browser at a local test server
.\run-dev.ps1 -Fullscreen                   # test the fullscreen browser view mode
.\run-dev.ps1 -PrintConfig                  # show the effective settings, don't launch
.\build-dev.ps1 -Clean                      # rebuild from scratch
.\build-dev.ps1 -Platform x86               # build 32-bit (x86) instead of x64
.\clean-dev.ps1                             # delete DevEnvironment\build again
```

Every script also supports `-Help` or `--help`.

---

### Trying the configuration without building

If you don't have Visual Studio Build Tools yet but do have Safe Exam Browser installed, you can exercise the development *configuration* — app switching, windowed browser, no lockdown — against that installed copy:

```powershell
.\run-dev.ps1 -App "C:\Program Files\SafeExamBrowser\SafeExamBrowser.exe"
```

This launches the chosen SEB with the dev config the same way double-clicking a `.seb` file would. It is safe for the same reason the normal flow is: the config is session-only (`sebConfigPurpose = 0`, still enforced), so that installation's persistent client settings are not written to, and nothing inside `Program Files` is modified.

---

## Testing the "Open in Safe Exam Browser" link

Assessment sites offer a button that launches SEB directly. It is a link using the `seb://` (or `sebs://`) URL scheme, and clicking it makes **Windows** launch whichever application owns that scheme — normally the installed, production SEB. No script is involved, so `run-dev.ps1` can never be reached that way.

This folder reproduces the same click-to-launch flow for development, using a scheme of its own:

```
seb://server/exam.seb      →  installed Safe Exam Browser   (unchanged, full lockdown)
sebdev://server/exam.seb   →  SEBDevHandler  →  run-dev.ps1  →  development SEB
```

### Setting it up

```powershell
.\register-url-handler.ps1                               # register the helper for your user
Start-Process .\seb-test-page.html                       # the stand-in page; click the button
.\check-last-run.ps1                                     # confirm the chain actually ran
```

Remove it again with `.\register-url-handler.ps1 -Unregister` (or `.\clean-dev.ps1`, since the handler script is in `build\`).

### Why this cannot disturb a real exam

The handler registers **only** `sebdev://` and `sebdevs://` in `HKCU:\Software\Classes` (user registry) — never `seb://` or `sebs://`. Nothing else on the machine claims those names, so Windows routes them without any system-wide default handler being changed. A genuine `seb://` exam link keeps opening the installed Safe Exam Browser exactly as before.

The trade-off is that the button has to be clicked on `seb-test-page.html`, not on the customer's live site, because their HTML says `seb://`. `seb-test-page.html` takes a URL and rewrites it the same way an assessment site does (`https://` → `sebdevs://`).

### Checking that the dev flow really ran

SEB opening is not proof, since the production SEB opening normally looks much the same. `.\check-last-run.ps1` walks the whole chain and reports each step:

```text
  ok  protocol handler  registered in HKCU:\Software\Classes (claims: sebdev, sebdevs)
  ok  handler ran       received: sebdevs://server/exam.seb
  ok  run-dev.ps1       run-dev.ps1 launched successfully
  ok  SEB running       development build (DevEnvironment\build)
  ok  config            development configuration was applied
  ok  dev mode          unlocked session (kiosk restrictions relaxed, app switching allowed)
```

Raw handler output is in `build\url-handler.log`; no new line means the click never reached the helper.

---

## What's in this folder

| File | Purpose |
| --- | --- |
| `SEBDevelopment.seb` | The development configuration — an unencrypted XML plist `.seb` file with relaxed restrictions. |
| `check-prereqs.ps1` | Diagnoses installed SDKs, .NET targeting packs, Visual Studio / MSBuild, and VC++ redistributables. |
| `check-prereqs.cmd` | CMD wrapper for `check-prereqs.ps1`. |
| `register-url-handler.ps1` | Registers `sebdev://` and `sebdevs://` in user registry to enable click-to-launch testing. |
| `register-url-handler.cmd` | CMD wrapper for `register-url-handler.ps1`. |
| `seb-test-page.html` | Local stand-in for the customer's "Open in Safe Exam Browser" page. |
| `check-last-run.ps1` | Reports whether a click actually reached the dev flow. Read-only. |
| `check-last-run.cmd` | CMD wrapper for `check-last-run.ps1`. |
| `build-dev.ps1` | Compiles `SafeExamBrowser.sln` (Debug configuration) into `DevEnvironment\build\Debug`. |
| `build-dev.cmd` | CMD wrapper for `build-dev.ps1`. |
| `run-dev.ps1` | Launches that build with `SEBDevelopment.seb`. |
| `run-dev.cmd` | CMD wrapper for `run-dev.ps1`. |
| `clean-dev.ps1` | Removes `DevEnvironment\build`. |
| `clean-dev.cmd` | CMD wrapper for `clean-dev.ps1`. |
| `seb-dev-common.ps1` | Shared paths, checks, tool detection, and output helpers. |
| `build/` | Generated: the Debug build, NuGet cache, handler script, and throwaway session configs. Git-ignored. |

---

## Prerequisites

* **.NET Framework 4.8 Developer Pack / Targeting Pack**: Required to compile the projects.
  Download from: https://dotnet.microsoft.com/download/dotnet-framework/net48
* **Visual Studio 2019 / 2022** (Community, Professional, Enterprise) or **Visual Studio Build Tools** with the *.NET desktop development* workload.
* **Visual C++ 2015–2022 Redistributable** (x64 / x86): Required by the embedded Chromium browser engine (CefSharp).
  Download from: https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist
* The open source tree does not contain proprietary binary security modules (`seb_x64.dll` / `seb_x86.dll`). The application detects their absence and runs smoothly in development mode.

---

## How development mode differs from a normal session

`SEBDevelopment.seb` is a standard `.seb` configuration file. `run-dev.ps1` passes it to the Debug build the same way a double-clicked config would be passed to SEB, and SEB applies it through its regular configuration pipeline. The relevant settings:

### Makes the machine usable while SEB runs

| Setting | Value | Effect |
| --- | --- | --- |
| `createNewDesktop` | `false` | Does not create a separate desktop; runs on the regular Windows desktop. |
| `killExplorerShell` | `false` | Windows Explorer and taskbar are not terminated. |
| `allowSwitchToApplications` | `true` | Process switching is not blocked; **Alt-Tab and clicking other windows work**. |
| `enableAppSwitcherCheck` | `false` | Using the app switcher is not treated as a violation. |
| `autoQuitApplications` | `false` | SEB does not terminate apps you already have open (Visual Studio, VS Code, terminals, etc.). |
| `detectStoppedProcess` | `false` | A process paused in the debugger is not treated as a violation. |
| `permittedProcesses` / `prohibitedProcesses` | empty | SEB neither requires nor kills any other application. |
| `sebServiceIgnore` | `true` | Runs without requiring the elevated `SafeExamBrowser.Service` Windows service. |
| `enableAltTab`, `enableStartMenu`, `enableCtrlEsc`, `enableAltF4` | `true` | Windows keys and hotkeys remain functional. |

### Makes debugging and UI testing practical

| Setting | Value | Effect |
| --- | --- | --- |
| `browserViewMode` | `0` (window) | Windowed at 1280×860 instead of covering the screen. `-Fullscreen` overrides this per launch. |
| `allowDeveloperConsole` | `true` | Chromium Developer Tools (Web Inspector / Console) available. |
| `browserWindowShowURL` | `3` (always) | The loaded URL is visible. |
| `enableBrowserWindowToolbar`, `showReloadButton`, `browserWindowAllowReload`, `allowBrowsingBackForward` | `true` | Reload and navigate while iterating on web content. |
| `allowScreenSharing`, `allowWindowCapture` | `true` | Screenshots and screen recording for UI tests. |
| `allowedDisplaysMaxNumber` `3`, `allowedDisplayBuiltinEnforce` `false`, `allowedDisplaysIgnoreFailure` `true` | | Multi-monitor dev setups are not rejected. |
| `allowQuit` `true`, empty quit/admin passwords, `allowPreferencesWindow` `true` | | Quit always works; settings UI is reachable. |
| `allowVirtualMachine` `true` | | Runs inside virtual machines. |
| `URLFilterEnable` `false`, `sendBrowserExamKey` `false` | | Arbitrary local test servers load; no Browser Exam Key header is required. |
| `enableScreenProctoring`, `jitsiMeetEnable`, `zoomEnable` | `false` | No proctoring in local development. |
| `logLevel` `1` (Debug) | | Verbose logs written to `%LOCALAPPDATA%\SafeExamBrowser\Logs`. |

The file itself is documented; read `SEBDevelopment.seb` for the full configuration.

---

## Why this cannot affect the production or examination build

This is enforced in three independent ways:

**1. No source code is changed by default.** This folder adds configuration files, shell scripts, and documentation. SEB's security logic, its default settings, and its production behavior are byte-for-byte what they were.

**2. The settings are session-only and never persisted.** `SEBDevelopment.seb` declares:

```xml
<key>sebConfigPurpose</key>
<integer>0</integer>
```

`0` represents starting an exam (`ConfigurationMode.Exam`). In [`SafeExamBrowser.Runtime/Operations/Session/ConfigurationOperation.cs`](../SafeExamBrowser.Runtime/Operations/Session/ConfigurationOperation.cs), that value makes SEB use in-memory settings for the active session only:

Nothing is written to `%APPDATA%\SafeExamBrowser\SebClientSettings.seb` or `%PROGRAMDATA%\SafeExamBrowser\SebClientSettings.seb`. When the dev session quits, the settings are discarded, and the persisted SEB client configuration is untouched. `run-dev.ps1` **refuses to launch** any configuration whose `sebConfigPurpose` is not `0`.

**3. The scripts stay inside this folder.** `build-dev.ps1` builds only the `Debug` configuration into `DevEnvironment\build`. It never builds Release and never installs to `Program Files`. By default `run-dev.ps1` launches only the build in `DevEnvironment\build`; `-App` is the one deliberate, explicit exception, and even then it only launches the chosen executable with a config file — it never modifies that installation, and reason 2 above still applies to it.

---

## Cautions

* **Do not save as client configuration from the Settings window.** The dev config enables `allowPreferencesWindow` so the settings UI can be tested, but choosing *Configure a client* when saving from that window writes persistent settings. Save as *Starting an exam*, or save to a file.
* **Do not derive an exam configuration from `SEBDevelopment.seb`.** Build exam configs from SEB's defaults instead; this file inverts security-relevant settings for developer convenience.
* `run-dev.ps1 -Url` and `-Fullscreen` write a throwaway copy to `DevEnvironment\build\session\`; the tracked `SEBDevelopment.seb` is never modified.

---

## Debugging with Visual Studio / VS Code

`run-dev.ps1` launches the same binaries Visual Studio builds, so either approach works:

* **Attach to Process:** Run `.\run-dev.ps1`, then in Visual Studio go to **Debug ▸ Attach to Process...** and select `SafeExamBrowser.exe` (or `SafeExamBrowser.Client.exe`).
* **Launch from Visual Studio:** Open `SafeExamBrowser.sln`, set `SafeExamBrowser.Runtime` as the Startup Project, open Project Properties ▸ **Debug**, and set **Command line arguments** to:
  ```text
  "..\..\..\DevEnvironment\SEBDevelopment.seb"
  ```
  Then press **F5**.

Session logs are written to `%LOCALAPPDATA%\SafeExamBrowser\Logs`.
