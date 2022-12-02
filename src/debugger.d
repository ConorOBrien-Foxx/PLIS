module plis.debugger;

import std.stdio;

bool debugging = false;

void debugPlis(T...)(string place, T args) {
    if(debugging) {
        writeln("\x1B[90m[", place, "]\x1B[0m ", args);
    }
}
