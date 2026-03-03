# Homebrew Distribution Setup

## 1. Build a release archive

In Xcode: **Product → Archive → Distribute App → Copy App**

## 2. Create the zip and GitHub release

```bash
zip -r PadIO-1.0.zip PadIO.app
shasum -a 256 PadIO-1.0.zip   # note the hash
gh release create v1.0 PadIO-1.0.zip --repo vgreg/PadIO --title "PadIO 1.0" --notes "Initial release"
```

## 3. Create the Homebrew tap repo

Create a new repo `vgreg/homebrew-tap` (general-purpose tap for any future projects) with this structure:

```
homebrew-tap/
  Casks/
    padio.rb
```

## 4. Cask formula

`Casks/padio.rb`:

```ruby
cask "padio" do
  version "1.0"
  sha256 "REPLACE_WITH_ACTUAL_SHA256"

  url "https://github.com/vgreg/PadIO/releases/download/v#{version}/PadIO-#{version}.zip"
  name "PadIO"
  desc "macOS menu bar daemon that maps game controller inputs to keyboard and mouse"
  homepage "https://www.vincentgregoire.com/PadIO"

  depends_on macos: ">= :sonoma"

  app "PadIO.app"

  zap trash: "~/.config/padio"
end
```

## 5. Install

```bash
brew install --cask vgreg/tap/padio
```
