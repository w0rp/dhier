module hier;

import std.range: isInputRange, isOutputRange;
import std.algorithm;
import std.regex: Regex, match;
import std.typecons: Unqual;

private alias Set(V) = void[0][V];

@nogc @safe pure nothrow
private bool contains(T, U)(inout(void[0][T]) set, auto ref inout(U) value)
if(is(Unqual!U : Unqual!T)) {
    return (value in set) !is null;
}

@safe pure nothrow
private void add(T, U)(ref void[0][T] set, auto ref U value)
if(is(U : T)) {
    set[value] = (void[0]).init;
}

/**
 * Given a range of values, create a set from that range.
 */
private auto toSet(InputRange)(InputRange inputRange)
if(isInputRange!InputRange) {
    Set!(typeof(inputRange.front)) set;

    foreach(value; inputRange) {
        set.add(value);
    }

    return set;
}

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

/**
 * This struct defines a collection of classes for outputting class hierarchy
 * information.
 */
struct ClassHierarchyInfo {
private:
    Set!(const(ClassInfo)) _classSet;
public:
    /**
     * Construct the class hierarchy info with an existing set of classes.
     */
    @safe pure nothrow
    this(Set!(const(ClassInfo)) classSet) {
        _classSet = classSet;
    }

    @disable this(this);

    /**
     * Returns: true if this object already knows about the given class
     * or interface.
     */
    @nogc @safe pure nothrow
    bool hasClass(const(ClassInfo) info) const {
        return _classSet.contains(info);
    }

    /**
     * Returns: The set of classes and interfaces currently held in the object.
     */
    @nogc @safe pure nothrow
    @property const(Set!(const(ClassInfo))) classSet() const {
        return _classSet;
    }

    /**
     * Returns: The set of classes and interfaces currently held in the object
     * as an InputRange, in some undefined order.
     */
    @nogc @system pure nothrow
    @property auto classes() const {
        return _classSet.byKey;
    }

    /**
     * Add just a class or interface to the object.
     *
     * Params:
     *     info = The ClassInfo object for a class or interface.
     */
    @safe pure nothrow
    void addClass(const ClassInfo info) {
        _classSet.add(info);
    }

    /**
     * Add a class and all super-types to the object.
     *
     * If this class has already been added to the object,
     *
     * Params:
     *     info = The ClassInfo object for a class or interface.
     */
    @safe pure nothrow
    void addClassWithAncestors(const ClassInfo info) {
        addClass(info);

        // Add inherited interfaces.
        foreach(face; info.interfaces) {
            if (!hasClass(face.classinfo)) {
                addClassWithAncestors(face.classinfo);
            }
        }

        // Add the base class of this class.
        if (info.base !is null && !hasClass(info.base)) {
            addClassWithAncestors(info.base);
        }
    }

    /**
     * Add a module and all contained classes with super types to the object.
     *
     * Params:
     *     mod = The module.
     */
    @trusted pure nothrow
    void addModule(const(ModuleInfo*) mod) {
        foreach(info; mod.localClasses) {
            addClassWithAncestors(info);
        }
    }

    /**
     * Add every module available to this object, from all of the modules
     * which can be seen through imports.
     */
    @trusted
    void addAbsolutelyEverything() {
        foreach(mod; ModuleInfo) {
            addModule(mod);
        }
    }
}

/**
 * Create a copy of the class hierarchy info object without class and
 * interface names matching the given regular expression.
 *
 * Params:
 *     hierInfo = The hierarchy information to copy.
 *     re = A regular expression for filtering out class and interface names.
 *
 * Returns: A copy of the hierarchy information without the matches.
 */
@trusted
ClassHierarchyInfo filterOut(ref ClassHierarchyInfo hierInfo, Regex!char re) {
    return typeof(return)(
        hierInfo
        .classes
        .filter!(x => !x.name.match(re))
        .toSet
    );
}

/// ditto
@safe
ClassHierarchyInfo filterOut(ClassHierarchyInfo hierInfo, Regex!char re) {
    return hierInfo.filterOut(re);
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
(auto ref ClassHierarchyInfo hier, R range) {
    void writeClassName(const(ClassInfo) info) {
        range.put('"');
        info.name.copy(range);
        range.put('"');
    }

    void writeEdges(const(ClassInfo) info) {
        // Write subclass -> interface
        foreach(face; info.interfaces) {
            if (face.classinfo in hier.classSet) {
                writeClassName(info);
                " -> ".copy(range);
                writeClassName(face.classinfo);
                ";\n".copy(range);
            }
        }

        // Write subclass -> superclass.
        if (info.base !is null && info.base in hier.classSet) {
            writeClassName(info);
            " -> ".copy(range);
            writeClassName(info.base);
            ";\n".copy(range);
        }
    }

    // Open the graph file.
    "digraph {\n".copy(range);
    "rankdir=BT;\n\n".copy(range);

    // Write all of the interface nodes up front with some settings which
    // can be applied to them.
    "node[rank=source, shape=box, color=blue, penwidth=2];\n".copy(range);
    "//Interface nodes.\n".copy(range);

    // List all of the interace nodes.
    foreach(info; hier.classes) {
        if (isInterface(info)) {
            writeClassName(info);
            ";\n".copy(range);
        }
    }

    // Set different node settings for classes.
    "\nnode[color=black];\n\n".copy(range);
    "//Class nodes.\n".copy(range);

    // List all of the class nodes.
    foreach(info; hier.classes) {
        if (!isInterface(info)) {
            writeClassName(info);
            ";\n".copy(range);
        }
    }

    range.put('\n');

    // Now write the edges out, which is the most important information.
    foreach(info; hier.classes) {
        writeEdges(info);
    }

    range.put('}');
}

/**
 * Write a DOT language description of the class and interface
 * hierarchies with just the class names to a DOT file.
 *
 * Params:
 *     hier = The hierarchy information.
 *     range = The output range.
 */
void writeNamesToDOT(R)(auto ref ClassHierarchyInfo hier, R range)
if (isOutputRange!(R, char)) {
    writeDOT!(IncludeAttributes.no, R)(hier, range);
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
"hier.Editable";
"hier.Tweakable";

node[color=black];

//Class nodes.
"hier.NotSoSpecialWidget";
"hier.Widget";

"hier.NotSoSpecialWidget" -> "hier.Widget";
"hier.Widget" -> "hier.Tweakable";
"hier.Tweakable" -> "hier.Editable";
}`;
}

// Test if the right DOT file will be outputted for some given class data.
// This does depend on the order of the associative arrays a little...
unittest {
    import std.array;
    import std.regex;

    ClassHierarchyInfo hierInfo;

    hierInfo.addClassWithAncestors(NotSoSpecialWidget.classinfo);

    // Filter out a few standard libraries classes/interfaces.
    hierInfo = hierInfo.filterOut(ctRegex!(
        `(^object\.|^std\.|^core.|^TypeInfo|^gc\.|rt\.)`));

    Appender!string appender;

    hierInfo.writeNamesToDOT(&appender);

    assert(appender.data == nameHierarchyDOT);
}

/**
 * Write a DOT language description of the class and interface hierarchies to
 * a DOT file with methods and attributes included. This should create a UML
 * style diagram.
 *
 * Params:
 *     hier = The hierarchy information.
 *     range = The output range.
 */
void writeUMLToDOT(R)(auto ref ClassHierarchyInfo hier, R range)
if (isOutputRange!(R, char)) {
    writeDOT!(IncludeAttributes.yes, R)(hier, range);
}


/**
 * This type contains a set of modules with some methods for conveniently
 * collecting modules. This type can be used for generating module dependency
 * graphs.
 */
struct ModuleDependencyInfo {
private:
    Set!(const(ModuleInfo*)) _moduleSet;
    Set!(const(ModuleInfo*)) _leafSet;
public:
    /**
     * Construct the class hierarchy info with an existing set of modules.
     */
    @safe pure nothrow
    this(Set!(const(ModuleInfo*)) moduleSet) {
        _moduleSet = moduleSet;
    }

    @disable this(this);

    /**
     * Returns: true if this object already knows about the given module.
     */
    @nogc @safe pure nothrow
    bool hasModule(const(ModuleInfo*) mod) const {
        return _moduleSet.contains(mod);
    }

    /**
     * Returns: true if this object knows about a module, and it is a leaf.
     */
    @nogc @trusted pure nothrow
    bool hasLeafModule(const(ModuleInfo*) mod) {
        return mod in _moduleSet && mod in _leafSet;
    }

    /**
     * Returns: true if this object knows about a module, and it is not a leaf.
     */
    @nogc @trusted pure nothrow
    bool hasDependentModule(const(ModuleInfo*) mod) {
        return mod in _moduleSet && mod !in _leafSet;
    }

    /**
     * Returns: The set of modules currently held in the object.
     */
    @nogc @safe pure nothrow
    @property const(Set!(const(ModuleInfo*))) moduleSet() const {
        return _moduleSet;
    }

    /**
     * Returns: The set of modules currently held in the object as an
     * InputRange, in some undefined order.
     */
    @nogc @system pure nothrow
    @property auto modules() const {
        return _moduleSet.byKey;
    }

    /**
     * Add a module to the object. The module will be marked as a leaf if it
     * has not already been added.
     *
     * Params:
     *     mod = The module.
     */
    @trusted pure nothrow
    void addModule(const(ModuleInfo*) mod) {
        if (!_moduleSet.contains(mod)) {
            _moduleSet.add(mod);
            _leafSet.add(mod);
        }
    }

    /**
     * Add a module with all of its dependencies, recursively walking through
     * dependent modules until all modules are discovered.
     *
     * The module will not be considered a leaf node, even if it has already
     * been added, nor will its dependencies.
     *
     * Params:
     *     mod = The module.
     */
    @trusted pure nothrow
    void addModuleWithDependencies(const(ModuleInfo*) mod) {
        _moduleSet.add(mod);
        _leafSet.remove(mod);

        // Add the imported module.
        foreach(importedModule; mod.importedModules) {
            if (!hasModule(importedModule)) {
                addModuleWithDependencies(importedModule);
            }
        }
    }

    /**
     * Add a module with all of its direct dependencies, just the modules
     * a module has imported.
     *
     * The module will not be considered a leaf node, however its dependencies
     * will be, unless they are added through some other means.
     *
     * Params:
     *     mod = The module.
     */
    @trusted pure nothrow
    void addModuleWithDirectDepdencies(const(ModuleInfo*) mod) {
        _moduleSet.add(mod);
        _leafSet.remove(mod);

        foreach(importedModule; mod.importedModules) {
            if (!hasModule(importedModule)) {
                addModule(importedModule);
            }
        }
    }

    /**
     * Add every module available to this object, from all of the modules
     * which can be seen through imports.
     */
    @trusted
    void addAbsolutelyEverything() {
        foreach(mod; ModuleInfo) {
            addModuleWithDependencies(mod);
        }
    }
}

/**
 * Create a copy of the module dependency info object without module names
 * matching the given regular expression.
 *
 * Params:
 *     dependencyInfo = The module dependency information to copy.
 *     re = A regular expression for filtering out module names.
 *
 * Returns: A copy of the dependency information without the matches.
 */
@trusted
ModuleDependencyInfo filterOut
(ref ModuleDependencyInfo dependencyInfo, Regex!char re) {
    return typeof(return)(
        dependencyInfo
        .modules
        .filter!(x => !x.name.match(re))
        .toSet
    );
}

/// ditto
@safe
ModuleDependencyInfo filterOut
(ModuleDependencyInfo dependencyInfo, Regex!char re) {
    return dependencyInfo.filterOut(re);
}

/**
 * Write a DOT language description of the module dependency graph to
 * a DOT file.
 *
 * Params:
 *     dependencyInfo = The module dependency information.
 *     range = The output range.
 */
void writeDOT(R)(auto ref ModuleDependencyInfo depInfo, R range) {
    import std.typecons;

    // We have to collect the edges we written in a set and make sure we
    // don't write them twice, as importedModules can contain a module several
    // times over.
    Set!(Tuple!(const(ModuleInfo)*, immutable(ModuleInfo)*)) writtenEdgeSet;

    void writeModuleName(const(ModuleInfo*) mod) {
        range.put('"');
        mod.name.copy(range);
        range.put('"');
    }

    void writeEdges(const(ModuleInfo*) mod) {
        foreach(importedModule; mod.importedModules) {
             if (depInfo.hasModule(importedModule)
             && !writtenEdgeSet.contains(tuple(mod, importedModule))) {
                writeModuleName(mod);
                " -> ".copy(range);
                writeModuleName(importedModule);
                ";\n".copy(range);

                writtenEdgeSet.add(tuple(mod, importedModule));
             }
        }
    }

    // Open the graph file.
    "digraph {\n".copy(range);
    "rankdir=BT;\n\n".copy(range);

    range.put('\n');

    // Set different node settings for modules.
    "\nnode[color=black];\n\n".copy(range);
    "//Module nodes.\n".copy(range);

    foreach(mod; depInfo.modules) {
        writeModuleName(mod);
        ";\n".copy(range);
    }

    foreach(mod; depInfo.modules) {
        if (depInfo.hasDependentModule(mod)) {
            writeEdges(mod);
        }
    }

    range.put('}');
}

/**
 * Write a DOT language description of the module dependency graph to
 * a DOT file. The modules will be ranked by the number of times they are
 * imported, and the lines will be drawn orthongonally.
 *
 * Params:
 *     dependencyInfo = The module dependency information.
 *     range = The output range.
 */
void writeRankedDOT(R)(auto ref ModuleDependencyInfo depInfo, R range) {
    import std.typecons;
    import std.conv: to;

    // We have to collect the edges we written in a set and make sure we
    // don't write them twice, as importedModules can contain a module several
    // times over.
    Set!(Tuple!(const(ModuleInfo)*, immutable(ModuleInfo)*)) writtenEdgeSet;
    // We need to track counted edges separately.
    Set!(Tuple!(const(ModuleInfo)*, immutable(ModuleInfo)*)) countedEdgeSet;
    // We need to keep a record of the incoming edge counts.
    size_t[const(ModuleInfo)*] incomingEdgeCountMap;

    void writeModuleName(const(ModuleInfo*) mod) {
        range.put('"');
        mod.name.copy(range);
        range.put('"');
    }

    // In order for the ranking to work, we have to write the numbers first
    // before the regular edges. So counting and writing edges has to be two
    // isolated procedures.
    void countEdges(const(ModuleInfo*) mod) {
        if (mod !in incomingEdgeCountMap) {
            // Set the incoming edge count for outgoing edges to 0 at first,
            // so we can rank modules which aren't imported anywhere too.
            incomingEdgeCountMap[mod] = 0;
        }

        foreach(importedModule; mod.importedModules) {
             if (depInfo.hasModule(importedModule)
             && !countedEdgeSet.contains(tuple(mod, importedModule))) {
                countedEdgeSet.add(tuple(mod, importedModule));

                // Increment or set the incoming edge count.
                auto countPtr = importedModule in incomingEdgeCountMap;

                if (countPtr) {
                    *countPtr = *countPtr + 1;
                } else {
                    incomingEdgeCountMap[importedModule] = 1;
                }
             }
        }
    }

    void writeEdges(const(ModuleInfo*) mod) {
        foreach(importedModule; mod.importedModules) {
             if (depInfo.hasModule(importedModule)
             && !writtenEdgeSet.contains(tuple(mod, importedModule))) {
                writeModuleName(mod);
                " -> ".copy(range);
                writeModuleName(importedModule);
                ";\n".copy(range);

                writtenEdgeSet.add(tuple(mod, importedModule));
             }
        }
    }

    // Open the graph file.
    "digraph {\n".copy(range);
    "splines=ortho;\n".copy(range);
    "rankdir=BT;\n\n".copy(range);

    range.put('\n');

    // count the incoming edges and so on.
    foreach(mod; depInfo.modules) {
        countEdges(mod);
    }

    // Now let's reverse the mapping to count -> module_list.
    const(ModuleInfo*)[][size_t] countToVertexMap;

    foreach(mod, count; incomingEdgeCountMap) {
        auto arrayPtr = count in countToVertexMap;

        if (arrayPtr) {
            *arrayPtr ~= mod;
        } else {
            countToVertexMap[count] = [mod];
        }
    }

    // Now we can write the counts out as edges by themself.
    // This will trick Graphviz into drawing things in ranks.
    bool firstCount = true;

    "node[shape=none]".copy(range);

    foreach(count; countToVertexMap.keys.sort) {
        if (!firstCount) {
            "->".copy(range);
        }

        count.to!string.copy(range);

        firstCount = false;
    }

    "[arrowhead=none];\n".copy(range);

    // Now we'll write {rank=same 1; foo; bar;} to set the node rankings.
    foreach(count, modList; countToVertexMap) {
        "{rank=same ".copy(range);

        count.to!string.copy(range);
        "; ".copy(range);

        foreach(mod; modList) {
            writeModuleName(mod);
            "; ".copy(range);
        }

        "}\n".copy(range);
    }

    // Now we can write our actual nodes and edges out for the proper graph.
    "//Module nodes.\n".copy(range);

    foreach(mod; depInfo.modules) {
        writeModuleName(mod);
        "[shape=box, color=black]".copy(range);
        ";\n".copy(range);
    }

    foreach(mod; depInfo.modules) {
        if (depInfo.hasDependentModule(mod)) {
            writeEdges(mod);
        }
    }

    range.put('}');
}
