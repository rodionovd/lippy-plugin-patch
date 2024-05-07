## lippy-plugin-patch

This is a runtime patch for [Lippy.sketchplugin](https://github.com/abynim/lippy/) by **@abynim** that makes it fully compatible with the latest version of Sketch (v100 at the time of writing).

> [!TIP]
> A pre-patched plugin is avaiable to download [here](https://github.com/rodionovd/lippy-plugin-patch/releases).


### Approach

Instead of manually re-writing `-[LippyMainViewController showEditorForContext:]` and a few other methods to use proper Sketch APIs (which might have been easier in retrospect 🗿) this patch intercepts various `-valueForKeyPath:` calls made by the plugin on Sketch data models, and makes them return stuff in a format that Lippy expects. See [LippyPatcher.m](./LippyPatcher.m) for details.
