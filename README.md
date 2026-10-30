# cedo

A “minimal” text editor for macOS.

## Concept

- **For writing** — Made for long-form text, not code.
- **Plain files, quiet history** — Files stay plain text in a folder. Git keeps their history behind the scenes, and the folder remains a normal repository other tools can use.
- **Terminal alongside** — Covers what the editor can't do yet, and is a place to consult coding agents while you write.

## Requirements

- macOS 14 or later
- Xcode with Swift 5.10 or later
- The Metal Toolchain, which the terminal library [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) needs to build:

  ```sh
  xcodebuild -downloadComponent MetalToolchain
  ```

## Build and run

Run directly during development:

```sh
make run
```

Build an app bundle at `build/cedo.app`, and open it:

```sh
make app
make open
```

Install it into `/Applications` (set `INSTALL_DIR` to install elsewhere):

```sh
make install
make install INSTALL_DIR=~/Applications
```

`make build` builds the debug version, `make test` runs the tests, and `make clean` removes build outputs.

## Usage

- Open a folder with ⌘O, then select a file to edit. Changes save automatically.
- Toggle the terminal with ⌃\`.
- Toggle the debug log, which shows saves, commits and other background activity, with ⌥⌘L.
- In Git repositories, edited files are committed after five idle minutes, when switching files or folders, or on quit. View commits in **History**.
