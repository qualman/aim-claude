#!/bin/zsh
# Swift Testing's macro plugin isn't on the default search path under Command Line Tools.
set -e
cd "$(dirname "$0")/.."
exec swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing "$@"
