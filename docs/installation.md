# Installation

## Homebrew (recommended)

```bash
brew install --cask vgreg/tap/padio
```

This installs PadIO to your Applications folder. Launch it from Spotlight or the Applications folder — it runs as a menu bar icon with no main window.

!!! note "Gatekeeper warning"
    PadIO is not notarized, so macOS will show a security warning on first launch. To bypass it, right-click the app → **Open** → **Open** in the dialog. You only need to do this once.

## Build from source

### Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15 or later

### Steps

1. Clone the repository:

    ```bash
    git clone https://github.com/vgreg/PadIO.git
    cd PadIO
    ```

2. Open in Xcode and build:

    ```bash
    open PadIO.xcodeproj
    ```

    Press **⌘R** to build and run, or **⌘B** to build only.

3. For a release build, use **Product → Archive → Distribute App → Copy App**.

## First launch

On first launch, PadIO appears as a menu bar icon. You'll need to:

1. **Grant Accessibility permission** — click the menu bar icon and select **Grant Accessibility Access**, or go to **System Settings → Privacy & Security → Accessibility** and add PadIO.
2. **Create a config file** — PadIO reads from `~/.config/padio/config.json`. Without it, the app runs but ignores all controller input. See [Getting Started](getting-started.md) for how to set one up.
