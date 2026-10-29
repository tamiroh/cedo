# cedo

A “minimal” text editor for macOS.

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
- In Git repositories, edited files are committed after five idle minutes, when switching files or folders, or on quit. View commits in **History**.
