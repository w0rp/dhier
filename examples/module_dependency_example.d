/**
 * Example D source file for the hierarchy generator.
 *
 * rdmd example.d | dot -Tpng > example.png
 */

import std.stdio;
import std.regex;

import hier;

void main(string[] argv) {
    ModuleGraph graph;

    graph.addAbsolutelyEverything();

    graph = graph.filterOut(ctRegex!(
        `(^module_dependency_example$|^hier$|^object$|^core\.|^gc\.|^rt\.)`));

    graph.writeDOT(stdout.lockingTextWriter);
}

