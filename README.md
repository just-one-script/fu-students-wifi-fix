# FU-Students Wi-Fi Fix

[Tiếng Việt](README.vi.md)

This repository helps Linux users connect to these networks at FPT University, Can Tho campus:

- `FU-Students`
- `FU-Students Alpha`
- `FU-Students_6G`

The script switches only the Wi-Fi backend to `iwd`; NetworkManager remains the single owner of all Wi-Fi profiles and connection decisions.

## 1. Usage

```bash
git clone https://github.com/just-one-script/fu-students-wifi-fix.git
cd fu-students-wifi-fix
chmod +x fu-students-wifi-fix.sh
sudo ./fu-students-wifi-fix.sh --setup
```

Setup requires an interactive terminal. It prompts for the university username/student ID and password before making any system changes.

After setup, normal home networks, hotspots, and captive portals can still be added from the operating system's Wi-Fi dialog.

Other commands:

```bash
sudo ./fu-students-wifi-fix.sh --check
sudo ./fu-students-wifi-fix.sh --update-credentials
sudo ./fu-students-wifi-fix.sh --ca-cert /path/to/current-fpt-ca
sudo ./fu-students-wifi-fix.sh --ca-cert system
sudo ./fu-students-wifi-fix.sh --rollback
./fu-students-wifi-fix.sh --help
```

`--check` verifies that all managed NetworkManager profiles contain credentials, a CA certificate source, and the expected authentication domain. It never prints the password, but it cannot tell whether the password or certificate chain will be accepted by the network.

## 2. What setup changes

Setup:

1. Installs and starts `iwd` if needed.
2. Backs up the previous backend config and matching native iwd profiles.
3. Writes `/etc/NetworkManager/conf.d/wifi_backend.conf`:

   ```ini
   [device]
   wifi.backend=iwd
   wifi.iwd.autoconnect=false
   ```

4. Restarts NetworkManager.
5. Creates or updates these NetworkManager profiles with PEAP/MSCHAPV2 credentials, CA validation for `fun.cantho`, and autoconnect priority `100`:

   ```text
   fu-students-wifi-fix:FU-Students
   fu-students-wifi-fix:FU-Students Alpha
   fu-students-wifi-fix:FU-Students_6G
   ```

`iwd-config-path` is deliberately left at its default value, `auto`, so NetworkManager mirrors profile changes into iwd. Setting `wifi.iwd.autoconnect=false` keeps NetworkManager responsible for autoconnect, retries, priorities, desktop dialogs, and every non-university Wi-Fi network.

Setup first uses the distribution's PEM system CA bundle. NetworkManager's `system-ca-certs` setting is not used because the iwd backend does not support it directly. If certificate validation fails:

```bash
sudo ./fu-students-wifi-fix.sh --ca-cert /path/to/current-ca-cert
```

PEM, DER, and PKCS#12 inputs are accepted. The script converts the selected CA to PEM, checks that it is a non-expired CA certificate, stores it at `/var/lib/fu-students-wifi-fix/fpt-radius-ca.pem`, and prints its SHA-256 fingerprint. Use `--ca-cert system` to return to the system bundle. Reconnect after changing CA mode.

The script does not disable, mask, or uninstall `wpa_supplicant`; leaving it installed makes rollback safer.

## 3. Rollback

```bash
sudo ./fu-students-wifi-fix.sh --rollback
```

Rollback removes only the `fu-students-wifi-fix:*` NetworkManager profiles and the CA copy installed by this script, restores the previous backend configuration and native iwd profiles when backed up, restores the previous iwd service state, and restarts NetworkManager. It does not uninstall packages.

**Rebooting after rollback is recommended because NetworkManager and iwd can retain runtime state.**

## 4. Troubleshooting

```bash
sudo ./fu-students-wifi-fix.sh --check
NetworkManager --print-config
nmcli connection show
journalctl -u NetworkManager -u iwd -b
```

If credentials may be wrong:

```bash
sudo ./fu-students-wifi-fix.sh --update-credentials
```

Old profiles named exactly like the SSIDs are not modified by this script. If one interferes with the managed profile, remove it explicitly after confirming its name with `nmcli connection show`.

## 5. Files and profiles affected

- `/etc/NetworkManager/conf.d/wifi_backend.conf`
- NetworkManager's distribution-specific persistent profile store
- iwd's profile store, indirectly through NetworkManager's built-in conversion
- `/var/lib/fu-students-wifi-fix/fpt-radius-ca.pem`, when a custom CA is selected
- `/var/backups/fu-students-wifi-fix/`
- `/var/lib/fu-students-wifi-fix/`

## 6. References

- [NetworkManager.conf reference](https://networkmanager.dev/docs/api/latest/NetworkManager.conf.html)
- [NetworkManager profile settings](https://networkmanager.dev/docs/api/latest/nm-settings-nmcli.html)

## 7. License

GNU General Public License v3.0. See [LICENSE](LICENSE).
