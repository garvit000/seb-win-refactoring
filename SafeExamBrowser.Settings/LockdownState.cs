/*
 * Copyright (c) 2026 ETH Zürich, IT Services
 * 
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

using System;

namespace SafeExamBrowser.Settings
{
	public static class LockdownState
	{
		/// <summary>
		/// Whether window/app switching (Alt+Tab, Win key, trackpad gestures) is dynamically unlocked.
		/// Defaults to false (Strict Proctored Exam Lockdown).
		/// </summary>
		public static bool SwitchingUnlocked { get; set; } = false;

		public static event Action Unlocked;
		public static event Action Locked;

		public static void NotifyUnlocked()
		{
			SwitchingUnlocked = true;
			Unlocked?.Invoke();
		}

		public static void NotifyLocked()
		{
			SwitchingUnlocked = false;
			Locked?.Invoke();
		}
	}
}
