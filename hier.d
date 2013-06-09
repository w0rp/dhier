/*
Copyright (c) 2013, w0rp <devw0rp@gmail.com>
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

import std.stdio;
import std.range;
import std.algorithm;
import std.array;
import std.regex;

/++
 + This module defines a set of algorithms for printing information for
 + class hierarchies.
 +/

/**
 * Params:
 *     info = A ClassInfo object.
 *
 * Returns: true if the ClassInfo object represents an interface.
 */
@safe pure nothrow
bool isInterface(const ClassInfo info) {
    return info.base is null && info !is Object.classinfo;
}

struct HierarchyInfo {
private:
    bool[const(ClassInfo)] _classSet;
    bool[const(ClassInfo)] _interfaceSet;
public:
    /**
     * Returns: true if this object already knows about the given class.
     */
    @safe pure nothrow
    bool hasClass(const(ClassInfo) info) const {
        return info in _classSet || info in _interfaceSet;
    }

    /**
     * Returns: The set of classes currently held in the object.
     */
    @property @trusted pure nothrow
    const(bool[ClassInfo]) classSet() const {
        return cast(const(bool[ClassInfo])) _classSet;
    }

    /**
     * Returns: The set of interfaces currently held in the object.
     */
    @property @trusted pure nothrow
    const(bool[ClassInfo]) interfaceSet() const {
        return cast(const(bool[ClassInfo])) _interfaceSet;
    }


    /**
     * Add just a class to the object.
     *
     * Params:
     *     face = The interface description.
     */
    @safe pure nothrow
    void addClass(const ClassInfo info) {
        if (info.isInterface) {
            _interfaceSet[info] = true;
        } else {
            _classSet[info] = true;
        }
    }

    /**
     * Add a class and all super-types to the object.
     *
     * Params:
     *     face = The interface description.
     */
    @safe pure nothrow
    void addClassWithAncestors(const ClassInfo info) {
        addClass(info);

        foreach(face; info.interfaces) {
            if (face.classinfo !in _interfaceSet) {
                addClassWithAncestors(face.classinfo);
            }
        }

        if (info.base !is null) {
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
            if (!hasClass(info)) {
                addClassWithAncestors(info);
            }
        }
    }

    /// Add every imported module to the object.
    @trusted
    void addAbsolutelyEverything() {
        foreach(mod; ModuleInfo) {
            addModule(mod);
        }
    }
}

/**
 * Create a copy of the hierarchy info object without class and interface
 * names matching the given regular expression.
 *
 * Params:
 *     hierInfo = The hierarchy information to copy.
 *     re = A regular expression for filtering out class and interface names.
 *
 * Returns: A copy of the hierarchy information without the matches.
 */
HierarchyInfo filterOut(HierarchyInfo hierInfo, Regex!char re) {
    HierarchyInfo filteredCopy;

    foreach(info, _; hierInfo.classSet) {
        if (!info.name.match(re)) {
            filteredCopy._classSet[info] = true;
        }
    }

    foreach(info, _; hierInfo.interfaceSet) {
        if (!info.name.match(re)) {
            filteredCopy._interfaceSet[info] = true;
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
 * Write a dot language description of the hierarchy information to an
 * output range.
 *
 * Params:
 *     hier = The hierarchy information.
 *     range = The output range.
 */
@trusted
void writeDOT(R)(HierarchyInfo hier, R range)
if (isOutputRange!(R, char)) {
    void writeLabel(ClassInfo info) {
        range.put('"');
        info.name.copy(range);
        range.put('"');
    }

    void writeEdges(ClassInfo info) {
        foreach(face; info.interfaces) {
            if (face.classinfo in hier.interfaceSet) {
                range.put('\t');
                writeLabel(info);
                " -> ".copy(range);
                writeLabel(face.classinfo);
                ";\n".copy(range);
            }
        }

        if (info.base !is null && info.base in hier.classSet) {
            range.put('\t');
            writeLabel(info);
            " -> ".copy(range);
            writeLabel(info.base);
            ";\n".copy(range);
        }
    }

    "digraph {\n".copy(range);
    "\trankdir=BT;\n\n".copy(range);
    "\tnode[rank=source, shape=box, color=blue, penwidth=2];\n".copy(range);
    "\t//Interface nodes.\n".copy(range);

    // List all interface nodes up front so the basic settings apply to them.
    foreach(face, _; hier.interfaceSet) {
        range.put('\t');
        writeLabel(face);
        ";\n".copy(range);
    }

    // Set different node settings for classes.
    "\n\tnode[color=black];\n\n".copy(range);
    "\t//Class nodes.\n".copy(range);

    // List all of the class nodes.
    foreach(cls, _; hier.classSet) {
        range.put('\t');
        writeLabel(cls);
        ";\n".copy(range);
    }

    if (hier.classSet.length > 0) {
        range.put('\n');
    }

    foreach(face, _; hier.interfaceSet) {
        writeEdges(face);
    }

    foreach(cls, _; hier.classSet) {
        writeEdges(cls);
    }

    range.put('}');
}
