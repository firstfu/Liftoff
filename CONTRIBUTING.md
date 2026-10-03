# Contributing to Liftoff

Liftoff is built by one person, so every bit of help is noticed. The three easiest ways in:

## 1. Fix a translation
All interface text lives in one file: [`Liftoff/Resources/Localizable.xcstrings`](Liftoff/Resources/Localizable.xcstrings).
The keys are the Traditional Chinese source text; each language is an entry underneath.

- Edit the value for your language and open a pull request. No need to build anything.
- **System terms must match your macOS exactly** (System Settings, Accessibility, Hot Corners, Trash…). Check the real strings: macOS ships every language, e.g. `plutil -convert json -o - /System/Library/ExtensionKit/Extensions/SecurityPrivacyExtension.appex/Contents/Resources/Localizable.loctable`.
- Keep placeholders (`%lld`, `%@`) unchanged; if you reorder them, number all of them (`%1$@`, `%2$lld`).
- Spotted a mistake but don't want to fix it? Use the [translation issue template](https://github.com/firstfu/Liftoff/issues/new?template=translation_fix.yml).

## 2. Add a missing app to Smart Organize
[`Liftoff/Resources/AppCategories.json`](Liftoff/Resources/AppCategories.json) maps each app's bundle ID to a folder — one line per app:

```json
"com.example.MyApp": {"folder": "productivity", "app": "My App.app", "name": "My App"}
```

Folder keys: `developer`, `productivity`, `communication`, `browser`, `media`, `design`, `utilities`, `cloud`, `ai`, `education`, `finance`, `games`, `lifestyle`.
Find an app's bundle ID with `defaults read "/Applications/My App.app/Contents/Info.plist" CFBundleIdentifier`.

## 3. Report a bug
Please include your macOS version, what you expected, and what happened. For anything involving window previews, say whether Screen Recording and Accessibility are granted.

## Building and testing
```sh
brew install xcodegen
xcodegen generate
xcodebuild -project Liftoff.xcodeproj -scheme Liftoff -derivedDataPath build test
```
The project keeps hard performance limits (open < 3 ms, search < 8 ms per keystroke, 0 dropped frames, 0% CPU idle). After touching anything on a hot path, run `scripts/selftest.sh` and compare the report.

By contributing you agree that your work is released under the project's [GPLv3](LICENSE) license.
