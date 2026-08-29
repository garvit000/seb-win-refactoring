/*
 * Copyright (c) 2026 ETH Zürich, IT Services
 * 
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using SafeExamBrowser.Settings;
using SafeExamBrowser.Settings.Applications;
using SafeExamBrowser.Settings.Browser;
using SafeExamBrowser.Settings.Security;
using SafeExamBrowser.Settings.UserInterface;

namespace SafeExamBrowser.Configuration.ConfigurationData
{
	internal class DataProcessor
	{
		internal void Process(IDictionary<string, object> rawData, AppSettings settings)
		{
			ProcessDefault(settings);
			CalculateConfigurationKey(rawData, settings);
		}

		internal void ProcessDefault(AppSettings settings)
		{
			AllowBrowserToolbarForReloading(settings);
			InitializeBrowserHomeFunctionality(settings);
			InitializeClipboardSettings(settings);
			InitializeProctoringSettings(settings);
			RemoveLegacyBrowsers(settings);
#if DEBUG
			ApplyDevRelaxations(settings);
#endif
		}

		private void AllowBrowserToolbarForReloading(AppSettings settings)
		{
			if (settings.Browser.AdditionalWindow.AllowReloading && settings.Browser.AdditionalWindow.ShowReloadButton)
			{
				settings.Browser.AdditionalWindow.ShowToolbar = true;
			}

			if (settings.Browser.MainWindow.AllowReloading && settings.Browser.MainWindow.ShowReloadButton)
			{
				settings.Browser.MainWindow.ShowToolbar = true;
			}
		}

		private void CalculateConfigurationKey(IDictionary<string, object> rawData, AppSettings settings)
		{
			using (var algorithm = new SHA256Managed())
			using (var stream = new MemoryStream())
			using (var writer = new StreamWriter(stream))
			{
				Json.Serialize(rawData, writer);

				writer.Flush();
				stream.Seek(0, SeekOrigin.Begin);

				var hash = algorithm.ComputeHash(stream);
				var key = BitConverter.ToString(hash).ToLower().Replace("-", string.Empty);

				settings.Browser.ConfigurationKey = key;
			}
		}

		private void InitializeBrowserHomeFunctionality(AppSettings settings)
		{
			settings.Browser.MainWindow.ShowHomeButton = settings.Browser.UseStartUrlAsHomeUrl || !string.IsNullOrWhiteSpace(settings.Browser.HomeUrl);
			settings.Browser.HomePasswordHash = settings.Security.QuitPasswordHash;
		}

		private void InitializeClipboardSettings(AppSettings settings)
		{
			settings.Browser.UseIsolatedClipboard = settings.Security.ClipboardPolicy == ClipboardPolicy.Isolated;
			settings.Keyboard.AllowCtrlC = settings.Security.ClipboardPolicy != ClipboardPolicy.Block;
			settings.Keyboard.AllowCtrlV = settings.Security.ClipboardPolicy != ClipboardPolicy.Block;
			settings.Keyboard.AllowCtrlX = settings.Security.ClipboardPolicy != ClipboardPolicy.Block;
		}

		private void InitializeProctoringSettings(AppSettings settings)
		{
			settings.Proctoring.Enabled = settings.Proctoring.ScreenProctoring.Enabled;
		}

		private void RemoveLegacyBrowsers(AppSettings settings)
		{
			var legacyBrowsers = new List<WhitelistApplication>();

			foreach (var application in settings.Applications.Whitelist)
			{
				var isEnginePath = application.ExecutablePath?.Contains("xulrunner") == true;
				var isFirefox = application.ExecutableName?.Equals("firefox.exe", StringComparison.OrdinalIgnoreCase) == true;
				var isXulRunner = application.ExecutableName?.Equals("xulrunner.exe", StringComparison.OrdinalIgnoreCase) == true;

				if (isEnginePath && (isFirefox || isXulRunner))
				{
					legacyBrowsers.Add(application);
				}
			}

			foreach (var legacyBrowser in legacyBrowsers)
			{
				settings.Applications.Whitelist.Remove(legacyBrowser);
			}
		}

#if DEBUG
		private void ApplyDevRelaxations(AppSettings settings)
		{
			if (Environment.GetEnvironmentVariable("SEB_DEV_RELAXED_LOCKDOWN") == "1")
			{
				settings.Security.KioskMode = KioskMode.None;
				settings.Security.AllowTermination = true;
				settings.Browser.MainWindow.FullScreenMode = false;
				settings.Browser.MainWindow.RelativeWidth = 100;
				settings.Browser.MainWindow.RelativeHeight = 100;
				settings.Browser.MainWindow.Position = WindowPosition.Center;
				settings.Browser.MainWindow.ShowToolbar = true;
				settings.Browser.MainWindow.AllowAddressBar = true;
				settings.Browser.MainWindow.UrlPolicy = UrlPolicy.Always;
				settings.Browser.MainWindow.AllowReloading = true;
				settings.Browser.MainWindow.ShowReloadButton = true;
				settings.Browser.MainWindow.AllowBackwardNavigation = true;
				settings.Browser.MainWindow.AllowForwardNavigation = true;
				settings.Browser.MainWindow.AllowDeveloperConsole = true;
				settings.Browser.AdditionalWindow.AllowDeveloperConsole = true;
				settings.Keyboard.AllowAltTab = true;
				settings.Keyboard.AllowAltF4 = true;
				settings.Keyboard.AllowCtrlEsc = true;
				settings.Keyboard.AllowAltEsc = true;
				settings.Service.IgnoreService = true;
			}
		}
#endif
	}
}
