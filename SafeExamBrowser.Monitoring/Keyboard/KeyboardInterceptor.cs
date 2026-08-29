/*
 * Copyright (c) 2026 ETH Zürich, IT Services
 * 
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

using System;
using System.Diagnostics;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Input;
using SafeExamBrowser.Logging.Contracts;
using SafeExamBrowser.Monitoring.Contracts.Keyboard;
using SafeExamBrowser.Settings;
using SafeExamBrowser.Settings.Monitoring;
using SafeExamBrowser.WindowsApi.Contracts;
using SafeExamBrowser.WindowsApi.Contracts.Events;

namespace SafeExamBrowser.Monitoring.Keyboard
{
	public class KeyboardInterceptor : IKeyboardInterceptor
	{
		private Guid? hookId;
		private readonly ILogger logger;
		private readonly INativeMethods nativeMethods;
		private readonly KeyboardSettings settings;

		public static bool SwitchingUnlocked => LockdownState.SwitchingUnlocked;

		public KeyboardInterceptor(ILogger logger, INativeMethods nativeMethods, KeyboardSettings settings)
		{
			this.logger = logger;
			this.nativeMethods = nativeMethods;
			this.settings = settings;
		}

		public void Start()
		{
			hookId = nativeMethods.RegisterKeyboardHook(KeyboardHookCallback);
		}

		public void Stop()
		{
			if (hookId.HasValue)
			{
				nativeMethods.DeregisterKeyboardHook(hookId.Value);
			}
		}

		private bool KeyboardHookCallback(int keyCode, KeyModifier modifier, KeyState state)
		{
			var key = KeyInterop.KeyFromVirtualKey(keyCode);

			// Developer Hotkeys:
			// Unlock: Shift + Alt + S OR Ctrl + Alt + S
			// Lock:   Shift + Alt + L OR Ctrl + Alt + S (when already unlocked)
			var hasAlt = modifier.HasFlag(KeyModifier.Alt);
			var hasShift = modifier.HasFlag(KeyModifier.Shift);
			var hasCtrl = modifier.HasFlag(KeyModifier.Ctrl);

			var isS = key == Key.S || keyCode == 83;
			var isL = key == Key.L || keyCode == 76;

			if (hasAlt && (hasShift || hasCtrl) && isS)
			{
				if (state == KeyState.Pressed)
				{
					if (!LockdownState.SwitchingUnlocked)
					{
						UnlockSwitching();
					}
					else if (hasCtrl)
					{
						LockSwitching();
					}
				}
				return true;
			}

			if (hasAlt && (hasShift || hasCtrl) && isL)
			{
				if (state == KeyState.Pressed && LockdownState.SwitchingUnlocked)
				{
					LockSwitching();
				}
				return true;
			}

			var block = false;

			// Proctored Lockdown mode vs Unlocked Switching mode
			if (!LockdownState.SwitchingUnlocked)
			{
				// In Proctored Mode, strictly block all window/task switching keys and gestures
				block |= key == Key.Apps;
				block |= key == Key.LWin;
				block |= key == Key.RWin;
				block |= hasAlt && key == Key.Tab;
				block |= hasAlt && key == Key.Escape;
				block |= hasAlt && key == Key.Space;
				block |= hasCtrl && key == Key.Escape;
			}
			else
			{
				// In Unlocked Mode, allow Alt+Tab, Win key, and switching shortcuts
				block |= key == Key.Apps;
				block |= key == Key.LWin && !settings.AllowSystemKey;
				block |= key == Key.RWin && !settings.AllowSystemKey;
				block |= hasAlt && key == Key.Escape && !settings.AllowAltEsc;
				block |= hasCtrl && key == Key.Escape && !settings.AllowCtrlEsc;
			}

			// General restrictions
			block |= key == Key.Escape && modifier == KeyModifier.None && !settings.AllowEsc;
			block |= key == Key.F1 && !settings.AllowF1;
			block |= key == Key.F2 && !settings.AllowF2;
			block |= key == Key.F3 && !settings.AllowF3;
			block |= key == Key.F4 && !settings.AllowF4;
			block |= key == Key.F5 && !settings.AllowF5;
			block |= key == Key.F6 && !settings.AllowF6;
			block |= key == Key.F7 && !settings.AllowF7;
			block |= key == Key.F8 && !settings.AllowF8;
			block |= key == Key.F9 && !settings.AllowF9;
			block |= key == Key.F10 && !settings.AllowF10;
			block |= key == Key.F11 && !settings.AllowF11;
			block |= key == Key.F12 && !settings.AllowF12;
			block |= key == Key.PrintScreen && !settings.AllowPrintScreen;

			block |= hasAlt && key == Key.F4 && !settings.AllowAltF4;

			block |= hasCtrl && key == Key.C && !settings.AllowCtrlC;
			block |= hasCtrl && key == Key.V && !settings.AllowCtrlV;
			block |= hasCtrl && key == Key.X && !settings.AllowCtrlX;

			block |= modifier.HasFlag(KeyModifier.Injected) && !settings.AllowInjected;

			if (block)
			{
				Log(key, keyCode, modifier, state);
			}

			return block;
		}

		private void UnlockSwitching()
		{
			logger.Info("==> [HOTKEY] Window, Tab, and App switching UNLOCKED.");
			LockdownState.NotifyUnlocked();

			// Launch or restore secondary browser window (Microsoft Edge) on demand
			Task.Run(() =>
			{
				try
				{
					var edgeProcesses = Process.GetProcessesByName("msedge");
					if (edgeProcesses.Length == 0)
					{
						Process.Start(new ProcessStartInfo
						{
							FileName = "msedge.exe",
							Arguments = "--new-window https://www.bing.com",
							UseShellExecute = true
						});
					}
				}
				catch (Exception ex)
				{
					logger.Warn($"Could not launch msedge.exe: {ex.Message}");
				}
			});
		}

		private void LockSwitching()
		{
			logger.Info("==> [HOTKEY] Window, Tab, and App switching LOCKED (Proctored Mode).");
			LockdownState.NotifyLocked();
		}

		private void Log(Key key, int keyCode, KeyModifier modifier, KeyState state)
		{
			var modifierFlags = Enum.GetValues(typeof(KeyModifier)).OfType<KeyModifier>().Where(m => m != KeyModifier.None && modifier.HasFlag(m));
			var modifiers = modifierFlags.Any() ? String.Join(" + ", modifierFlags) + " + " : string.Empty;

			logger.Info($"Blocked '{modifiers}{key}' ({key} = {keyCode}) when {state.ToString().ToLower()}.");
		}
	}
}
