# PowerShell Webhook

Provides a simple way to execute PowerShell code on a PC, based on HTTP GET or POST requests to certain URLs.

Can, e.g., be used to control the Windows Night Light feature and your monitor brightness, with requests coming from your home automation system that also controls your lights.

# Setup

Download the files with GitHub's feature "Code > Local > Download ZIP" and extract them into a directory of your liking.

Open an elevated PowerShell command prompt and navigate to the directory.

Install the web server software [Pode](https://badgerati.github.io/Pode/) from [PowerShell Gallery](https://www.powershellgallery.com/packages/Pode) with:

```powershell
Install-Module -Name Pode
```

Run the setup script:

```powershell
.\Setup.ps1
```

Now you can run a webhook server in a non-elevated PowerShell command prompt:

```powershell
.\Example.ps1
```

Create your own webhook server script to define the names of your webhooks together with their PowerShell code, or edit an existing script.

Create an autostart shortcut in `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup` (for current user) or `%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs` (for all users). To hide the console window in the taskbar tray, use [Tray Valet](https://github.com/Enyium/tray-valet-rs) like so:

```
"C:\path\to\tray-valet.exe" --win-class ConsoleWindowClass --icon "C:\path\to\powershell-webhook.ico" --set-win-icon -- conhost powershell -File "C:\path\to\Example.ps1"
```

Of course, you can also use `pwsh` instead of `powershell`, if you installed it.

# License

Licensed under either of

* Apache License, Version 2.0
  ([LICENSE-APACHE](LICENSE-APACHE) or http://www.apache.org/licenses/LICENSE-2.0)
* MIT license
  ([LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT)

at your option.

# Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the work by you, as defined in the Apache-2.0 license, shall be dual licensed as above, without any additional terms or conditions.

# Credits

<a href="https://www.flaticon.com/free-icons/automation" title="automation icons">Automation icons created by Freepik - Flaticon</a>
