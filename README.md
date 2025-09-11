# screenshots.pak

A MinUI app for browsing your saved screenshots. Automatically organized by game/app.

## Requirements

This pak is designed and tested on the following MinUI Platforms and devices:
- `tg5040`: Trimui Brick

If you haven't installed [minui-screenshot-monitor-pak](https://github.com/josegonzalez/minui-screenshot-monitor-pak/) already, install it, configure a shortcut to take screenshots, and then use this pak to view the screenshots. 

## Installation

1. Mount your MinUI SD card.
2. Download the latest release from [GitHub releases](https://github.com/mikecosentino/Screenshots/releases). It will be named `Screenshots.pak.zip`.
3. Create the folder `/Tools/$PLATFORM/Screenshots.pak.`
4. Copy the zip file to `/Tools/$PLATFORM/Screenshots.pak.zip`.
4. Extract the zip in place, then delete the zip file.
5. Confirm that there is a `/Tools/$PLATFORM/Screenshots.pak/launch.sh` file on your SD card.
6. Unmount your SD Card and insert it into your MinUI device.

## Usage

- Browse to `Tools > Screenshots` and press `A` to enter the Pak. 
- Select a game with `A` to view that game's screenshots (ordered by date with newest at the top)
- `Left` or `right` buttons to scroll through that game's screenshots
- `X` while viewing a screenshot will prompt for delete confirmation

## Information
 
- `/.userdata/tg5040/Screenshots` stores a cache of games and their screenshots

## Acknowledgements

- [minui-list](https://github.com/josegonzalez/minui-list) by Jose Diaz-Gonzalez
- [minui-presenter](https://github.com/josegonzalez/minui-presenter) by Jose Diaz-Gonzalez
- [minui-gallery-pak](https://github.com/josegonzalez/minui-gallery-pak) by Jose Diaz-Gonzalez; which this pak is built off

