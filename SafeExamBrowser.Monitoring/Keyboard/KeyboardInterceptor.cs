/*
 * Copyright (c) 2026 ETH Zürich, IT Services
 * 
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

using System;
using System.Linq;
using System.Windows.Input;
using SafeExamBrowser.Logging.Contracts;
using SafeExamBrowser.Monitoring.Contracts.Keyboard;
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

		/// <summary>
		/// Controls whether window and app switching (Alt+Tab, Win key, trackpad gestures) is dynamically unlocked.
		/// Defaults to false (Strict Proctored Exam Lockdown).
		/// Toggleable via Shift + Alt + S (unlock) and Shift + Alt + L (relock).
		/// </summary>
		public static bool SwitchingUnlocked { get; set; } = false;

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

			// Developer Hotkeys: Shift + Alt + S (Unlock Switching) and Shift + Alt + L (Lock Switching)
			var isShiftAlt = modifier.HasFlag(KeyModifier.Alt) && modifier.HasFlag(KeyModifier.Shift);
			if (isShiftAlt)
			{
				if (key == Key.S)
				{
					if (state == KeyState.Pressed && !SwitchingUnlocked)
					{
						SwitchingUnlocked = true;
						logger.Info("==> [HOTKEY] Shift+Alt+S: Window, Tab, and App switching UNLOCKED.");
					}
					return true;
				}

				if (key == Key.L)
				{
					if (state == KeyState.Pressed && SwitchingUnlocked)
					{
						SwitchingUnlocked = false;
						logger.Info("==> [HOTKEY] Shift+Alt+L: Window, Tab, and App switching LOCKED (Proctored Mode).");
					}
					return true;
				}
			}

			var block = false;

			// Proctored Lockdown mode vs Unlocked Switching mode
			if (!SwitchingUnlocked)
			{
				// In Proctored Mode, strictly block all window/task switching keys and gestures
				block |= key == Key.Apps;
				block |= key == Key.LWin;
				block |= key == Key.RWin;
				block |= modifier.HasFlag(KeyModifier.Alt) && key == Key.Tab;
				block |= modifier.HasFlag(KeyModifier.Alt) && key == Key.Escape;
				block |= modifier.HasFlag(KeyModifier.Alt) && key == Key.Space;
				block |= modifier.HasFlag(KeyModifier.Ctrl) && key == Key.Escape;
			}
			else
			{
				// In Unlocked Mode, allow Alt+Tab, Win key, and switching shortcuts
				block |= key == Key.Apps;
				block |= key == Key.LWin && !settings.AllowSystemKey;
				block |= key == Key.RWin && !settings.AllowSystemKey;
				block |= modifier.HasFlag(KeyModifier.Alt) && key == Key.Escape && !settings.AllowAltEsc;
				block |= modifier.HasFlag(KeyModifier.Ctrl) && key == Key.Escape && !settings.AllowCtrlEsc;
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

			block |= modifier.HasFlag(KeyModifier.Alt) && key == Key.F4 && !settings.AllowAltF4;

			block |= modifier.HasFlag(KeyModifier.Ctrl) && key == Key.C && !settings.AllowCtrlC;
			block |= modifier.HasFlag(KeyModifier.Ctrl) && key == Key.V && !settings.AllowCtrlV;
			block |= modifier.HasFlag(KeyModifier.Ctrl) && key == Key.X && !settings.AllowCtrlX;

			block |= modifier.HasFlag(KeyModifier.Injected) && !settings.AllowInjected;

			if (block)
			{
				Log(key, keyCode, modifier, state);
			}

			return block;
		}

		private void Log(Key key, int keyCode, KeyModifier modifier, KeyState state)
		{
			var modifierFlags = Enum.GetValues(typeof(KeyModifier)).OfType<KeyModifier>().Where(m => m != KeyModifier.None && modifier.HasFlag(m));
			var modifiers = modifierFlags.Any() ? String.Join(" + ", modifierFlags) + " + " : string.Empty;

			logger.Info($"Blocked '{modifiers}{key}' ({key} = {keyCode}) when {state.ToString().ToLower()}.");
		}
	}
}
