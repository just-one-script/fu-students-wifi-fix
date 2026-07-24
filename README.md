# FU-Students Wi-Fi Fix

[Tiếng Việt](README.vi.md)

Fix connection issues with the `FU-Students` Wi-Fi network on some Linux distributions at FPT University, Can Tho campus.

## 1. Problem

Some Linux distributions, including common Fedora and Ubuntu installations, use NetworkManager with `wpa_supplicant` as the default Wi-Fi backend.

At FPT University, Can Tho campus, this setup may fail to connect to the `FU-Students` Wi-Fi network. In observed cases, switching NetworkManager to use `iwd` as its Wi-Fi backend fixes the issue.

There is one important detail: the normal OS network settings UI may still fail even after NetworkManager is switched to the `iwd` backend. A common symptom is that the credential dialog opens, but after clicking **Connect**, nothing happens. Clicking the same Wi-Fi network again opens the same credential dialog repeatedly.

For these networks, the reliable path is to let `iwd` own the 802.1x profiles directly. This script therefore prompts for your university Wi-Fi credentials and writes iwd profiles instead of relying on the desktop network settings dialog to create them.

Configured SSIDs:

- `FU-Students`
- `FU-Students Alpha`
- `FU-Students_6G`

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

## 6. Manual verification

Check that NetworkManager is configured to use `iwd`:

```bash
NetworkManager --print-config | grep -i 'wifi.backend'
```

Check that NetworkManager iwd profile conversion is disabled:

```bash
NetworkManager --print-config | grep -i 'iwd-config-path'
```

Check that `iwd` is running:

```bash
systemctl status iwd
```

List visible Wi-Fi networks:

```bash
nmcli dev wifi list
```

Check that the generated iwd profile exists:

```bash
sudo ls -l /var/lib/iwd/FU-Students.8021x
sudo ls -l '/var/lib/iwd/FU-Students Alpha.8021x'
sudo ls -l /var/lib/iwd/FU-Students_6G.8021x
```

Check NetworkManager logs:

```bash
journalctl -u NetworkManager -b
```

## 7. Troubleshooting

If connection still fails after running setup:

1. Check for missing or blank credential fields:

   ```bash
   sudo ./fu-students-wifi-fix.sh --check
   ```

2. If you may have mistyped your username/student ID or password, update the iwd profiles:

   ```bash
   sudo ./fu-students-wifi-fix.sh --update-credentials
   ```

3. Restart NetworkManager again:

   ```bash
   sudo systemctl restart NetworkManager
   ```

4. If you previously created broken profiles from the OS Wi-Fi dialog, delete those NetworkManager profiles:

   ```bash
   nmcli connection delete FU-Students
   nmcli connection delete 'FU-Students Alpha'
   nmcli connection delete FU-Students_6G
   ```

5. Do not recreate these networks from the OS Wi-Fi dialog. The direct iwd profiles should be used instead.
6. Confirm the iwd profiles exist:

   ```bash
   sudo ls -l /var/lib/iwd/FU-Students.8021x
   sudo ls -l '/var/lib/iwd/FU-Students Alpha.8021x'
   sudo ls -l /var/lib/iwd/FU-Students_6G.8021x
   ```

7. Reboot if NetworkManager or `iwd` appears stuck.
8. Check logs:

   ```bash
   journalctl -u NetworkManager -b
   journalctl -u iwd -b
   ```

## 8. Files changed by setup

Setup mode only writes to:

- `/etc/NetworkManager/conf.d/wifi_backend.conf`
- `/var/lib/iwd/FU-Students.8021x`
- `/var/lib/iwd/FU-Students Alpha.8021x`
- `/var/lib/iwd/FU-Students_6G.8021x`
- `/var/backups/fu-students-wifi-fix/`
- `/var/lib/fu-students-wifi-fix/`

Existing iwd profile files for the supported FU-Students SSIDs are backed up before generated profiles are written.

## 9. References

- [NetworkManager.conf reference](https://networkmanager.pages.freedesktop.org/NetworkManager/NetworkManager/NetworkManager.conf.html): documents `wifi.backend`, `wifi.iwd.autoconnect`, and `iwd-config-path`.

## 10. License

This project is licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE).
