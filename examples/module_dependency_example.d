/**
 * Example D source file for the hierarchy generator.
 *
 * rdmd example.d | dot -Tpng > example.png
 */

import std.stdio;
import std.regex;

import hier;

void main(string[] argv) {
    ModuleDependencyInfo depInfo;

    depInfo.addAbsolutelyEverything();

    depInfo = depInfo.filterOut(ctRegex!(
        `(^module_dependency_example$|^hier$|^object$|^core\.|^gc\.|^rt\.)`));

    depInfo.writeDOT(stdout.lockingTextWriter);
}

