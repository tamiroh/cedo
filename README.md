# cedo

A minimal text editor for macOS.

## Requirements

- macOS 14 or later
- Xcode (or the Swift toolchain) with Swift 5.10 or later

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

`make build` builds the debug version, and `make clean` removes build outputs.

## Usage

- **Open Folder…** (⌘O): open a folder as the project
- Click a file in the tree to show it in the editor
- **Save** (⌘S): save the current file

A `•` in the window title means the file has unsaved changes. If you switch files or folders with unsaved changes, cedo asks whether to save them.

Hidden files are not shown in the tree. Only UTF-8 text files can be opened.
