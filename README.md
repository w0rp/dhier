# D Class and Module Introspection

This repository provides some functionality for generating visual
representations of class hierarchy information.

## Running Examples

A class hierarchy example can be run by using one of the additional
configurations defined.

```
dub run -q --config=class_example | dot -Tpng > class_example.png
```

A module dependency example can be run by using another configuration.

```
dub run -q --config=module_example | dot -Tpng > module_example.png
```

The library also supports graphs of modules, ranked by the number of times they are imported.

```
dub run -q --config=ranked_module_example | dot -Tpng > ranked_module_example.png
```
