# FU-Students Wi-Fi Fix

[Tiếng Việt](README.vi.md)

Fix connection issues with the `FU-Students` Wi-Fi network on some Linux distributions at FPT University, Can Tho campus.

## 1. Problem

On some Linux systems, **NetworkManager + wpa_supplicant** may fail to connect to FPT University's Wi-Fi networks, including **FU-Students** at the Can Tho campus.

Switching NetworkManager to use **iwd** can resolve the connection issue. However, the desktop network settings may still fail to connect or repeatedly show the credential dialog.

To avoid this, this script configures **802.1x Wi-Fi profiles directly through iwd** and prompts for your university credentials.

### Configured SSIDs

- FU-Students
- FU-Students Alpha
- FU-Students_6G

## 2. Supported systems

Setup mode supports systems using:

- `dnf`, such as Fedora
- `apt-get`, such as Ubuntu or Debian

> [!note]
>
> Other distributions may still work if `iwd` is installed manually first, but package installation is not automated for them.

## 3. Usage

```bash
git clone https://github.com/just-one-script/fu-students-wifi-fix.git
cd fu-students-wifi-fix
chmod +x fu-students-wifi-fix.sh
sudo ./fu-students-wifi-fix.sh --setup
```

The script will ask whether to create iwd profiles for the FU-Students Wi-Fi networks. Choose yes, then enter your university Wi-Fi username/student ID and password.

> [!important]
>
> After the script finishes, do not create these networks again from the OS Wi-Fi dialog. iwd should connect automatically when one of the configured networks is visible and the credentials are correct.

To show usage, supported flags, and troubleshooting:

```bash
./fu-students-wifi-fix.sh
# or
./fu-students-wifi-fix.sh --help
```

## 4. Check or fix mistyped credentials

If you accidentally mistyped your username/student ID or password, do not rollback. Update the generated iwd profiles instead:

```bash
sudo ./fu-students-wifi-fix.sh --update-credentials
```

The script will prompt for your credentials again, rewrite all three FU-Students iwd profiles, validate that the credential fields are not blank, then restart `iwd` and NetworkManager.

To check whether the generated profiles exist and have non-empty credential fields:

```bash
sudo ./fu-students-wifi-fix.sh --check
```

This check can detect missing profile files and blank username/password fields, but it cannot prove the password is correct unless the network accepts the connection.

## 5. Rollback

To revert the changes made by setup mode:

```bash
sudo ./fu-students-wifi-fix.sh --rollback
```

Rollback will:

- Restore the previous NetworkManager config if one was backed up.
- Remove the config file if setup created it from scratch.
- Restore previous iwd profile files for the supported FU-Students SSIDs if setup backed them up.
- Remove generated iwd profiles if setup created them from scratch.
- Restore the previous `iwd` service enabled/running state when possible.
- Restart NetworkManager.

Rollback does not uninstall `iwd`. Package removal is intentionally avoided because `iwd` may be used by other networks or system tools.

> [!note]
>
> After rollback, the script will ask whether you want to reboot immediately. Rebooting is recommended before testing Wi-Fi again because NetworkManager and `iwd` can keep runtime state that is not fully reset by restarting NetworkManager alone. If you choose not to reboot immediately, reboot manually later.

## 6. License

This project is licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE).
