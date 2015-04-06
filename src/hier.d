module hier;

import std.range: isInputRange, isOutputRange;
import std.algorithm;
import std.regex: Regex, match;
import std.typecons: Unqual;

import dstruct.graph;
import dstruct.map;

/**
 * Params:
 *     info = A ClassInfo object.
 *
 * Returns: true if the ClassInfo object represents an interface.
 */
@nogc @safe pure nothrow
bool isInterface(const ClassInfo info) {
    return info.base is null && info !is Object.classinfo;
}

/// An alias for a digraph over classes.
alias ClassGraph = Digraph!(const(ClassInfo));

/**
 * Add just a class or interface to the object.
 *
 * This simply adds a vertex to the graph.
 *
 * Params:
 *     graph = The graph to work with.
 *     info = The ClassInfo object for a class or interface.
 */
@trusted
void addClass(ref ClassGraph graph, const(ClassInfo) info) {
    graph.addVertex(info);
}

/**
 * Add a class and all super-types to the object.
 *
 * Params:
 *     graph = The graph to add ancestors into.
 *     info = The ClassInfo object for a class or interface.
 */
@trusted
void addClassWithAncestors(ref ClassGraph graph, const(ClassInfo) info) {
    graph.addVertex(info);

    // Add inherited interfaces.
    foreach(face; info.interfaces) {
        graph.addEdge(info, face.classinfo);
        graph.addClassWithAncestors(face.classinfo);
    }

    // Add the base class of this class.
    if (info.base !is null) {
        graph.addEdge(info, info.base);
        graph.addClassWithAncestors(info.base);
    }
}

/**
 * Add a module and all contained classes with super types to the object.
 *
 * Params:
 *     graph = The graph to add a module into.
 *     mod = The module.
 */
@trusted
void addModule(ref ClassGraph graph, const(ModuleInfo*) mod) {
    foreach(info; mod.localClasses) {
        graph.addClassWithAncestors(info);
    }
}

/**
 * Add every module available to this object, from all of the modules
 * which can be seen through imports.
 *
 * Params:
 *     graph = The graph to add everything into.
 */
@trusted
void addAbsolutelyEverything(ref ClassGraph graph) {
    foreach(mod; ModuleInfo) {
        graph.addModule(mod);
    }
}

/*
digraph {
    rankdir=BT;

    node[rank=source, shape=box, color=blue, penwidth=2];
    // Interface nodes are listed here.
    B;
    D;

    node[color=black];

    A -> B;
    C -> B;
    D -> C;
}
*/

enum IncludeAttributes: bool { no, yes };

void writeDOT(IncludeAttributes includeAttributes, R)
(const(ClassGraph) graph, R range) {
    void writeClassName(const(ClassInfo) info) {
        range.put('"');
        info.name.copy(range);
        range.put('"');
    }

    // Open the graph file.
    "digraph {\n".copy(range);
    "rankdir=BT;\n\n".copy(range);

    // Write all of the interface nodes up front with some settings which
    // can be applied to them.
    "node[rank=source, shape=box, color=blue, penwidth=2];\n".copy(range);
    "//Interface nodes.\n".copy(range);

    // List all of the interace nodes.
    foreach(info; graph.vertices) {
        if (isInterface(info)) {
            writeClassName(info);
            ";\n".copy(range);
        }
    }

    // Set different node settings for classes.
    "\nnode[color=black];\n\n".copy(range);
    "//Class nodes.\n".copy(range);

    // List all of the class nodes.
    foreach(info; graph.vertices) {
        if (!isInterface(info)) {
            writeClassName(info);
            ";\n".copy(range);
        }
    }

    range.put('\n');

    // Now write the edges out, which is the most important information.
    foreach(edge; graph.edges) {
        writeClassName(edge.from);
        " -> ".copy(range);
        writeClassName(edge.to);
        ";\n".copy(range);
    }

    range.put('}');
}

/**
 * Write a DOT language description of the class and interface
 * hierarchies with just the class names to a DOT file.
 *
 * Params:
 *     graph = The class graph.
 *     range = The output range.
 */
void writeNamesToDOT(R)(const(ClassGraph) graph, R range)
if (isOutputRange!(R, char)) {
    writeDOT!(IncludeAttributes.no, R)(graph, range);
}

version(unittest) {
private:

interface Editable {}
interface Tweakable : Editable {}
interface Special {}
class Widget : Tweakable {}
class SpecialWidget : Widget {}
class SuperSpecialWidget : SpecialWidget, Special {}
class NotSoSpecialWidget : Widget {}

enum nameHierarchyDOT =
`digraph {
rankdir=BT;

node[rank=source, shape=box, color=blue, penwidth=2];
//Interface nodes.
"hier.Tweakable";
"hier.Editable";

node[color=black];

//Class nodes.
"hier.NotSoSpecialWidget";
"hier.Widget";

"hier.Tweakable" -> "hier.Editable";
"hier.NotSoSpecialWidget" -> "hier.Widget";
"hier.Widget" -> "hier.Tweakable";
}`;
}

// Test if the right DOT file will be outputted for some given class data.
// This does depend on the order of the associative arrays a little...
unittest {
    import std.array;
    import std.regex;

    ClassGraph graph;

    graph.addClassWithAncestors(NotSoSpecialWidget.classinfo);

    // Filter out a few standard libraries classes/interfaces.
    graph = graph.filterOut(ctRegex!(
        `(^object\.|^std\.|^core.|^TypeInfo|^gc\.|rt\.)`));

    Appender!string appender;

    graph.writeNamesToDOT(&appender);

    assert(appender.data == nameHierarchyDOT);
}

/**
 * Write a DOT language description of the class and interface hierarchies to
 * a DOT file with methods and attributes included. This should create a UML
 * style diagram.
 *
 * Params:
 *     graph = The class graph.
 *     range = The output range.
 */
void writeUMLToDOT(R)(const(ClassGraph) graph, R range)
if (isOutputRange!(R, char)) {
    writeDOT!(IncludeAttributes.yes, R)(graph, range);
}

/// An alias for a digraph over module.
alias ModuleGraph = Digraph!(const(ModuleInfo*));


/**
 * Add a module to the graph.
 *
 * This will simply call addVertex.
 *
 * Params:
 *     graph = The graph.
 *     mod = The module.
 */
@trusted pure nothrow
void addModule(ref ModuleGraph graph, const(ModuleInfo*) mod) {
    graph.addVertex(mod);
}

/**
 * The dependency strategy to use for adding module dependencies.
 */
enum Dependencies: ubyte {
    /// Add all dependencies (edges), recursively. This is the default option.
    all,
    /// Add only direct depdencies (edges), with no recursion.
    direct
}

/**
 * Add a module with all of its dependencies, recursively walking through
 * dependent modules until all modules are discovered.
 *
 * If a module dependency has already been added, the recursion for
 * module dependencies will stop there. This is to prevent infinite recursion.
 *
 * Params:
 *     graph = The graph.
 *     mod = The module.
 */
@trusted pure nothrow
void addModuleWithDependencies(Dependencies strategy = Dependencies.all)
(ref ModuleGraph graph, const(ModuleInfo*) mod) {
    graph.addVertex(mod);

    // Add the imported module.
    foreach(importedModule; mod.importedModules) {
        static if (strategy == Dependencies.all) {
            if (!graph.hasEdge(mod, importedModule)) {
                graph.addEdge(mod, importedModule);

                // Add recursive dependencies.
                graph.addModuleWithDependencies(importedModule);
            }
        } else {
            graph.addEdge(mod, importedModule);
        }
    }
}

/**
 * Add every module available to this object, from all of the modules
 * which can be seen through imports.
 *
 * Params:
 *     graph = The graph to add everything to.
 */
@trusted
void addAbsolutelyEverything(ref ModuleGraph graph) {
    foreach(mod; ModuleInfo) {
        graph.addModuleWithDependencies(mod);
    }
}

/**
 * Create a copy of the dependency graph without names matching the
 * given regular expression.
 *
 * Params:
 *     graph = The graph to copy.
 *     re = A regular expression for filtering out symbol names.
 *
 * Returns: A copy of the graph without the matches.
 */
@trusted
GraphType filterOut(GraphType)(const(GraphType) graph, Regex!char re)
if(is(GraphType == ClassGraph) || is(GraphType == ModuleGraph)) {
    GraphType newGraph;

    foreach(edge; graph.edges) {
        if (!edge.from.name.match(re) && !edge.to.name.match(re)) {
            newGraph.addEdge(edge.from, edge.to);
        }
    }

    return newGraph;
}

/**
 * Write a DOT language description of the module dependency graph to
 * a DOT file.
 *
 * Params:
 *     graph = The module dependency graph.
 *     range = The output range.
 */
void writeDOT(R)(const(ModuleGraph) graph, R range) {
    void writeModuleName(const(ModuleInfo*) mod) {
        range.put('"');
        mod.name.copy(range);
        range.put('"');
    }

    // Open the graph file.
    "digraph {\n".copy(range);
    "rankdir=BT;\n\n".copy(range);

    range.put('\n');

    // Set different node settings for modules.
    "\nnode[color=black];\n\n".copy(range);
    "//Module nodes.\n".copy(range);

    foreach(mod; graph.vertices) {
        writeModuleName(mod);
        ";\n".copy(range);
    }

    foreach(edge; graph.edges) {
        writeModuleName(edge.from);
        " -> ".copy(range);
        writeModuleName(edge.to);
        ";\n".copy(range);
    }

    range.put('}');
}

/**
 * Write a DOT language description of the module dependency graph to
 * a DOT file. The modules will be ranked by the number of times they are
 * imported, and the lines will be drawn orthongonally.
 *
 * Params:
 *     graph = The module dependency graph.
 *     range = The output range.
 */
void writeRankedDOT(R)(const(ModuleGraph) graph, R range) {
    import std.array;
    import std.typecons;
    import std.conv: to;

    void writeModuleName(const(ModuleInfo*) mod) {
        range.put('"');
        mod.name.copy(range);
        range.put('"');
    }

    // Open the graph file.
    "digraph {\n".copy(range);
    "splines=ortho;\n".copy(range);
    "rankdir=BT;\n\n".copy(range);

    range.put('\n');

    // Count up the incoming edges for a module.
    HashMap!(const(ModuleInfo)*, size_t) incomingEdgeCountMap;

    foreach(edge; graph.edges) {
        incomingEdgeCountMap.setDefault(edge.to) += 1;
    }

    // Invert the map: count => [module, ...]
    HashMap!(size_t, const(ModuleInfo)*[])  countToVertexMap;

    foreach(item; incomingEdgeCountMap.byKeyValue) {
        countToVertexMap.setDefault(item.value) ~= item.key;
    }

    bool firstCount = true;

    "node[shape=none]".copy(range);

    // Now write the ranks, in order, in their own subgraph.
    foreach(count; countToVertexMap.byKey.array.sort) {
        if (!firstCount) {
            "->".copy(range);
        }

        count.to!string.copy(range);

        firstCount = false;
    }

    "[arrowhead=none];\n".copy(range);

    // Now we'll write {rank=same 1; foo; bar;} to set the node rankings.
    foreach(item; countToVertexMap.byKeyValue) {
        "{rank=same ".copy(range);

        item.key.to!string.copy(range);
        "; ".copy(range);

        foreach(mod; item.value) {
            writeModuleName(mod);
            "; ".copy(range);
        }

        "}\n".copy(range);
    }

    // Now we can write our actual nodes and edges out for the proper graph.
    "//Module nodes.\n".copy(range);

    foreach(mod; graph.vertices) {
        writeModuleName(mod);
        "[shape=box, color=black]".copy(range);
        ";\n".copy(range);
    }

    foreach(edge; graph.edges) {
        writeModuleName(edge.from);
        " -> ".copy(range);
        writeModuleName(edge.to);
        ";\n".copy(range);
    }

    range.put('}');
}
