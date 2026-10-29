# cedo

A “minimal" text editor for macOS.

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

- **Open Folder…** (⌘O): open a folder as the project
- Click a file in the tree to show it in the editor
- **Show Terminal** (⌃\`): toggle a terminal on the right, running your login shell in the project folder

cedo saves automatically a moment after you stop typing, and whenever you switch files, switch to another app, or quit. If the open file is changed by something else, such as a command in the terminal, cedo reloads it; if you were editing it at the same moment, cedo asks which version to keep.

If the folder is a Git repository, cedo commits the files you edit once you pause: five minutes without editing, switching to another file or folder, or quitting. Only files edited in cedo go into these commits; anything else you have staged is left alone. Use **History** above the editor to see a file's commits.

Hidden files are not shown in the tree. Only UTF-8 text files can be opened.
