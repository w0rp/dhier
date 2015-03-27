module hier;

import std.stdio;
import std.range;
import std.algorithm;
import std.array;
import std.regex;

/++
 + This module defines a set of algorithms for printing information for
 + class hierarchies and other module information.
 +/

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
    bool[const(ClassInfo)] _classSet;
public:
    @safe pure nothrow
    this(this) {
        // Copy the set in a rather convoluted way, so it can be done with
        // the right attributes applied to the method.
        auto oldClassSet = _classSet;

        _classSet = null;

        try {
            foreach(key, _; oldClassSet) {
                _classSet[key] = true;
            }
        } catch(Exception) {}
    }

    /**
     * Returns: true if this object already knows about the given class
     * or interface.
     */
    @nogc @safe pure nothrow
    bool hasClass(const(ClassInfo) info) const {
        return (info in _classSet) !is null;
    }

    /**
     * Returns: The set of classes and interfaces currently held in the object.
     */
    @nogc @trusted pure nothrow
    @property const(bool[ClassInfo]) classSet() const {
        return cast(const(bool[ClassInfo])) _classSet;
    }


    /**
     * Add just a class or interface to the object.
     *
     * Params:
     *     info = The ClassInfo object for a class or interface.
     */
    @safe pure nothrow
    void addClass(const ClassInfo info) {
        _classSet[info] = true;
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

    // BUG: ModuleInfo can't be const here, as localClasses is not const.
    /**
     * Add a module and all contained classes with super types to the object.
     *
     * Params:
     *     mod = The module.
     */
    @trusted pure nothrow
    void addModule(ModuleInfo* mod) {
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
ClassHierarchyInfo filterOut(ClassHierarchyInfo hierInfo, Regex!char re) {
    ClassHierarchyInfo filteredCopy;

    foreach(info, _; hierInfo.classSet) {
        if (!info.name.match(re)) {
            filteredCopy._classSet[info] = true;
        }
    }

    return filteredCopy;
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

/**
 * Write a DOT language description of the class hierarchy information to an
 * output range.
 *
 * Params:
 *     hier = The hierarchy information.
 *     range = The output range.
 */
void writeDOT(R)(ClassHierarchyInfo hier, R range)
if (isOutputRange!(R, char)) {
    void writeLabel(ClassInfo info) {
        range.put('"');
        info.name.copy(range);
        range.put('"');
    }

    void writeEdges(ClassInfo info) {
        // Write subclass -> interface
        foreach(face; info.interfaces) {
            if (face.classinfo in hier.classSet) {
                range.put('\t');
                writeLabel(info);
                " -> ".copy(range);
                writeLabel(face.classinfo);
                ";\n".copy(range);
            }
        }

        // Write subclass -> superclass.
        if (info.base !is null && info.base in hier.classSet) {
            range.put('\t');
            writeLabel(info);
            " -> ".copy(range);
            writeLabel(info.base);
            ";\n".copy(range);
        }
    }

    // Open the graph file.
    "digraph {\n".copy(range);
    "\trankdir=BT;\n\n".copy(range);

    // Write all of the interface nodes up front with some settings which
    // can be applied to them.
    "\tnode[rank=source, shape=box, color=blue, penwidth=2];\n".copy(range);
    "\t//Interface nodes.\n".copy(range);

    foreach(info, _; hier.classSet) {
        if (isInterface(info)) {
            range.put('\t');
            writeLabel(info);
            ";\n".copy(range);
        }
    }

    // Set different node settings for classes.
    "\n\tnode[color=black];\n\n".copy(range);
    "\t//Class nodes.\n".copy(range);

    // List all of the class nodes.
    foreach(info, _; hier.classSet) {
        if (!isInterface(info)) {
            range.put('\t');
            writeLabel(info);
            ";\n".copy(range);
        }
    }

    range.put('\n');

    // Now write the edges out, which is the most important information.
    foreach(info, _; hier.classSet) {
        writeEdges(info);
    }

    range.put('}');
}
