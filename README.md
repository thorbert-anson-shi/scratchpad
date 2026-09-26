# Scratchpad

Take notes without losing them

## Motivation

I have been trying to take notes but forgetting where I took them. I think this
is because I have not standardized where notes are stored.

Scratchpad just stores all my notes in one place, and allows me to access them
from anywhere in the terminal, instead of having to `ls` into the specific note
folder (which I usually forget about anyway).

In essence, it works almost like Obsidian and stores everything as an
unorganized collection of notes.

## Usage

It's a CLI with a few simple CRUD commands. All these notes are by default
stored in `$HOME/.local/share/scratchpad/`, and the default editor that's used
for `create` and `open` commands look at your terminal's `$EDTIOR` variable.

Run `scratchpad help` for more usage information.

## Building from source

```bash
zig build -Drelease
```

Gives you a small (~155KB) executable binary that you can either symlink to
`~/.local/bin/` or just use as is (i.e.
`./zig-out/bin/scratchpad [command] [options]`)
