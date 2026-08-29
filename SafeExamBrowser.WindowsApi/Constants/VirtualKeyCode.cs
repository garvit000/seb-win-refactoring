/*
 * Copyright (c) 2026 ETH Zürich, IT Services
 * 
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

namespace SafeExamBrowser.WindowsApi.Constants
{
	/// <remarks>
	/// See https://docs.microsoft.com/en-us/windows/desktop/inputdev/virtual-key-codes.
	/// </remarks>
	internal enum VirtualKeyCode
	{
		A = 0x41,
		L = 0x4C,
		Q = 0x51,
		S = 0x53,
		Delete = 0x2E,
		Shift = 0x10,
		LeftShift = 0xA0,
		RightShift = 0xA1,
		LeftAlt = 0xA4,
		LeftControl = 0xA2,
		LeftWindows = 0x5B,
		RightAlt = 0xA5,
		RightControl = 0xA3
	}
}
