# FU-Students Wi-Fi Fix

[Tiếng Việt](README.vi.md)

Fix connection issues with the `FU-Students` Wi-Fi network on some Linux distributions at FPT University, Can Tho campus.

## Problem

Some Linux distributions, including common Fedora and Ubuntu installations, use NetworkManager with `wpa_supplicant` as the default Wi-Fi backend.

At FPT University, Can Tho campus, this setup may fail to connect to the `FU-Students` Wi-Fi network. In observed cases, switching NetworkManager to use `iwd` as its Wi-Fi backend fixes the issue.

There is one important detail: the normal OS network settings UI may still fail even after NetworkManager is switched to the `iwd` backend. A common symptom is that the credential dialog opens, but after clicking **Connect**, nothing happens. Clicking the same Wi-Fi network again opens the same credential dialog repeatedly.

For these networks, the reliable path is to let `iwd` own the 802.1x profiles directly. The setup script therefore prompts for your university Wi-Fi credentials and writes iwd profiles instead of relying on the desktop network settings dialog to create them.

Configured SSIDs:

- `FU-Students`
- `FU-Students Alpha`
- `FU-Students_6G`

This repository provides:

- A setup script to configure NetworkManager to use `iwd`.
- A rollback script to revert the changes made by the setup script.
- Manual troubleshooting notes for affected students.

## What the setup script changes

`setup.sh` does the following:

1. Installs `iwd` if it is not already installed.
2. Backs up any existing NetworkManager Wi-Fi backend config at the target path.
3. Backs up existing iwd profile files for the supported FU-Students SSIDs, if present.
4. Writes this NetworkManager config:

   ```ini
   [main]
   iwd-config-path=

   [device]
   wifi.backend=iwd
   wifi.iwd.autoconnect=true
   ```

5. Prompts for your FU-Students username/student ID and password.
6. Writes these iwd profiles using the same PEAP/MSCHAPV2 credentials:

   ```text
   /var/lib/iwd/FU-Students.8021x
   /var/lib/iwd/FU-Students Alpha.8021x
   /var/lib/iwd/FU-Students_6G.8021x
   ```

7. Enables and starts the `iwd` service.
8. Restarts `iwd` and NetworkManager.
9. Records enough state for `rollback.sh` to undo only the changes made by `setup.sh`.

`iwd-config-path=` intentionally disables NetworkManager's iwd profile conversion. That prevents NetworkManager from overwriting the direct iwd profiles. `wifi.iwd.autoconnect=true` leaves iwd in charge of initiating connections from its own profiles.

The script intentionally does not disable, mask, or uninstall `wpa_supplicant`. NetworkManager should use `iwd` after the backend config is applied, and leaving `wpa_supplicant` alone makes rollback safer.

## Supported systems

The setup script supports systems using:

- `dnf`, such as Fedora
- `apt-get`, such as Ubuntu or Debian

Other distributions may still work if `iwd` is installed manually first, but package installation is not automated for them.

## Usage

Clone this repository, then run:

```bash
chmod +x setup.sh rollback.sh
sudo ./setup.sh
```

To show setup usage, supported flags, and troubleshooting:

```bash
./setup.sh --help
```

The script will ask whether to create iwd profiles for the FU-Students Wi-Fi networks. Choose yes, then enter your university Wi-Fi username/student ID and password.

After the script finishes, do not create these networks again from the OS Wi-Fi dialog. iwd should connect automatically when one of the configured networks is visible and the credentials are correct.

## Check or fix mistyped credentials

If you accidentally mistyped your username/student ID or password, do not rollback. Update the generated iwd profiles instead:

```bash
sudo ./setup.sh --update-credentials
```

The script will prompt for your credentials again, rewrite all three FU-Students iwd profiles, validate that the credential fields are not blank, then restart `iwd` and NetworkManager.

To check whether the generated profiles exist and have non-empty credential fields:

```bash
sudo ./setup.sh --check
```

This check does not print your password. It can detect missing profile files and blank username/password fields, but it cannot prove the password is correct unless the network accepts the connection.

## Rollback

To revert the changes made by `setup.sh`:

```bash
sudo ./rollback.sh
```

To show rollback usage and troubleshooting:

```bash
./rollback.sh --help
```

Rollback will:

- Restore the previous NetworkManager config if one was backed up.
- Remove the config file if setup created it from scratch.
- Restore previous iwd profile files for the supported FU-Students SSIDs if setup backed them up.
- Remove generated iwd profiles if setup created them from scratch.
- Restore the previous `iwd` service enabled/running state when possible.
- Restart NetworkManager.

Rollback does not uninstall `iwd`. Package removal is intentionally avoided because `iwd` may be used by other networks or system tools.

After rollback, the script will ask whether you want to reboot immediately. Rebooting is recommended before testing Wi-Fi again because NetworkManager and `iwd` can keep runtime state that is not fully reset by restarting NetworkManager alone. If you choose not to reboot immediately, reboot manually later.

## Manual verification

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

## Troubleshooting

If connection still fails after running setup:

1. Check for missing or blank credential fields:

   ```bash
   sudo ./setup.sh --check
   ```

2. If you may have mistyped your username/student ID or password, update the iwd profiles:

   ```bash
   sudo ./setup.sh --update-credentials
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

## Files changed by setup

The setup script only writes to:

- `/etc/NetworkManager/conf.d/wifi_backend.conf`
- `/var/lib/iwd/FU-Students.8021x`
- `/var/lib/iwd/FU-Students Alpha.8021x`
- `/var/lib/iwd/FU-Students_6G.8021x`
- `/var/backups/fu-students-wifi-fix/`
- `/var/lib/fu-students-wifi-fix/`

Existing iwd profile files for the supported FU-Students SSIDs are backed up before generated profiles are written.

## References

- [NetworkManager.conf reference](https://networkmanager.pages.freedesktop.org/NetworkManager/NetworkManager/NetworkManager.conf.html): documents `wifi.backend`, `wifi.iwd.autoconnect`, and `iwd-config-path`.

## License

This project is licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE).
