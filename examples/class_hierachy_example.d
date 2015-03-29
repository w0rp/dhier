/**
 * Example D source file for the hierarchy generator.
 *
 * rdmd example.d | dot -Tpng > example.png
 */

import std.stdio;
import std.regex;

import hier;

interface Editable {}
interface Tweakable : Editable {}
interface Special {}
class Widget : Tweakable {}
class SpecialWidget : Widget {}
class SuperSpecialWidget : SpecialWidget, Special {}
class NotSoSpecialWidget : Widget {}

void main(string[] argv) {
    ClassHierarchyInfo hierInfo;

    hierInfo.addAbsolutelyEverything();

    // Filter out a few standard libraries classes/interfaces.
    hierInfo = hierInfo.filterOut(ctRegex!(
        `(^object\.|^std\.|^core\.|^TypeInfo|^gc\.|^rt\.)`));

    hierInfo.writeNamesToDOT(stdout.lockingTextWriter);
}

