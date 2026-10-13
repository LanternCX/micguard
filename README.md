# MicGuard

A macOS background utility that restores the previous microphone once when a newly connected input device takes over the default input. Audio output is left unchanged.

Uses Core Audio device notifications without continuous polling. Starts at login and does not record audio or send data.

## Behavior

- Accepts the current microphone at startup.
- When a new input device appears, watches for a switch to it for two seconds.
- If the previous microphone is still connected, attempts to restore it once. Further switches are accepted.
- Accepts switches to existing devices and fallback selections when the previous microphone disconnects.

The previous microphone can be any input device, not just the built-in microphone.

## Install

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/LanternCX/micguard/main/install.sh)"
```

Requires Apple's Command Line Tools to compile the Swift source. If they are missing, the script requests installation; complete it and run the command again.

Starts immediately after installation. Run the same command to update. Tested on macOS 15.7.2.

## Stop

Stop the service and disable startup at login:

```sh
launchctl disable "gui/$(id -u)/local.micguard"
launchctl bootout "gui/$(id -u)/local.micguard"
```

Run the install command again to re-enable and start the service.

## Uninstall

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/LanternCX/micguard/main/install.sh)" -- --uninstall
```

Removes the service, installed files, and logs.

## Limitations

- Corrects input changes after they occur. Bluetooth headphones may briefly enter call mode.
- Applications with their own microphone selection must be configured separately.
- Core Audio does not report whether a switch was manual or automatic. A manual selection of a newly connected device within the two-second window may be reverted once; selecting it again is allowed.
- Automatic switches outside the connection window are allowed, as are further switches after the first correction. This utility does not lock the input device.
- Physical reconnection, sleep/wake, and login behavior have not been verified.

## Status

```sh
"$HOME/Library/Application Support/MicGuard/micguard" --status
launchctl print "gui/$(id -u)/local.micguard"
```

The command prints the current input, built-in microphone, and output device IDs. The current input does not need to match the built-in microphone.

Installed files:

- Program and log: `~/Library/Application Support/MicGuard/`
- LaunchAgent: `~/Library/LaunchAgents/local.micguard.plist`

## Build from source

```sh
git clone https://github.com/LanternCX/micguard.git
cd micguard
bash install.sh
```

Written in Swift using Core Audio and AppKit, with no third-party dependencies.

Run the connection policy tests:

```sh
mkdir -p .build
xcrun swiftc -D POLICY_TESTS Sources/MicGuard.swift Tests/ConnectionPolicyTests.swift -o .build/policy-tests
.build/policy-tests
```
