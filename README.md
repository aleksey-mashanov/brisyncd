# brisyncd - macOS display brightness synchronization daemon

This daemon (user agent) can be used to synchronize the brightness of an
external display with a main (integrated) display. This is especially useful if
the brightness of your main display is automatically controlled by an ambient
light sensor (Macbook Pro, for example).

brisyncd receives notifications from the system about displays
connection/disconnection and automatically selects display to get the
brightness from and displays to apply the brightness to.

## Usage

Just run `brisyncd` to start synchronization with default options. See `brisyncd -h`
for more information.

## Configuration

Additional configuration can be provided by a configuration file.
If no `--config` option provided `brisyncd` reads configuration from
`~/.brisyncd.json` and `/usr/local/etc/brisyncd.json` (the first found of them).
Configuration file is a JSON with the following structure (all fields are optional,
see `brisyncd -h` for detailed description):

```yaml
{
    "source": "Color LCD",  # name of the source display
    "min": 0,               # default minimum brightness level (default: 0)
    "max": 100,             # default maximum brightness level (default: 100)
    "gamma": 1.0,           # default brightness gamma correction (default: 1.0)
    "contrast": null,       # default contrast (default: null)
    "targets": {            # dictionary of targets with custom configuration
        "DELL U2720Q": {    # keys of the dict are names of the target displays
            "min": 35,      # minimum brightness level
            "max": 85,      # maximum brightness level
            "gamma": 2.0,   # brightness gamma correction
            "contrast": 75  # normal contrast
        }
    },
    "targetsOnly": true     # manage known targets only (default: false)
}
```
