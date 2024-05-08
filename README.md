## lippy-plugin-patch

> [!WARNING]
> **@abynim** was kind enough to grant me access to the original Lippy source code, so I brought all those compatibility patches upstream.
> Which means, go download [an official plugin](https://github.com/abynim/lippy/) instead – it works fine now; don't use this patch.

This is a runtime patch for [Lippy.sketchplugin](https://github.com/abynim/lippy/) by **@abynim** that makes it fully compatible with the latest version of Sketch (v100 at the time of writing).

### Approach

Instead of manually re-writing `-[LippyMainViewController showEditorForContext:]` and a few other methods to use proper Sketch APIs (which might have been easier in retrospect 🗿) this patch intercepts various `-valueForKeyPath:` calls made by the plugin on Sketch data models, and makes them return stuff in a format that Lippy expects. See [LippyPatcher.m](./LippyPatcher.m) for details.
