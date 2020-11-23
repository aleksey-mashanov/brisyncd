# brisyncd - macOS display brightness synchronization daemon

This daemon (user agent) can be used to synchronize the brightness of an
external display with a main (integrated) display. This is especially useful if
the brightness of your main display is automatically controlled by an ambient
light sensor (Macbook Pro, for example).

brisyncd receives notifications from the system about displays
connection/disconnection and automatically selects display to get the
brightness from and displays to apply the brightness to.

## Installation

### Using [brew](https://brew.sh/)

```sh
brew install aleksey-mashanov/brisyncd/brisyncd
brew services start brisyncd
```

### Manual

```sh
swift build -c release
cp `swift build -c release --show-bin-path`/brisyncd /usr/local/sbin/
cp io.github.aleksey-mashanov.brisyncd.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/io.github.aleksey-mashanov.brisyncd.plist
```

## Configuration

To make all your displays look alike in the full range of the main display
brightness tuning of the transfer function is required. This can be done using
four parameters: `min`, `max`, `gamma` and `contrast`.

`brisyncd` reads configuration from `~/.brisyncd.json` and `/usr/local/etc/brisyncd.json`
(the first found of them, can be overridden using `--config` command-line option).
Configuration file is a JSON with the following structure (all fields are optional,
comments here are for readability, they must be omitted in the config file):

```yaml
{
    "source": "Color LCD",  # name of the source display
    "min": 0,               # default minimum brightness level (default: 0)
    "max": 100,             # default maximum brightness level (default: 100)
    "gamma": 1.0,           # default brightness gamma correction (default: 1.0)
    "contrast": null,       # default contrast (default: null)
    "interval": 50,         # default update interval, ms. (default: 50)
    "targets": {            # dictionary of targets with custom configuration
        "DELL U2720Q": {    # keys of the dict are names of the target displays
            "min": 35,      # minimum brightness level
            "max": 85,      # maximum brightness level
            "gamma": 2.2,   # brightness gamma correction
            "contrast": 75, # normal contrast
            "interval": 50  # update interval, ms.
        }
    },
    "targetsOnly": true     # manage known targets only (default: false)
}
```

See `brisyncd help config` for more information.

The simplest way to create custom configuration is to dump a configuration detected by brisyncd
to a file and then modify it:

```sh
brisyncd config > ~/.brisyncd.json
```

`brisyncd` reads configuration file on startup so don't forget to restart it after modification:

```sh
brew services restart brisyncd
```

## Why brisyncd

* brisyncd receives notifications from the system when the main display brightness changes.
* Brightness is synchronized in real-time, with no visible delays.
* There are no timers, no background and periodic jobs which can consume the battery.
* brisyncd just does its job - no UI, no keyboard shortcuts, no additional features.
* brisyncd does not use `AppleLMUController` so it is compatible with the latest MacBook Pro.
* Can be tuned for displays with different peak brightness and brightness function.
* Can use contrast to darken display beyond 0% brightness.
* Supports heterogenous multi-display configurations.

## Displays supported

brisyncd uses [DDC/CI](https://en.wikipedia.org/wiki/Display_Data_Channel) to control display
brightness so it works for displays which support this specification.

Docking stations are known to not support DDC/CI proxying.
