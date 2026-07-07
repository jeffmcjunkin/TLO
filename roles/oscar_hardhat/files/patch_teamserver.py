#!/usr/bin/env python3
# Patch for HardHatC2 V0.3.03-Alpha teamserver compile break.
#
# In this tag, PluginService.GetImpPostProcPlugin() and the pre-proc plugin's
# .Value return the plugin *interfaces* (IExtImplant_TaskPostProcess /
# IExtImplant_TaskPreProcess), but ExtImplantHandleComms_Base.cs calls a
# base-class method (HandleDataChunking, defined on ExtImplant_TaskPostProcess_Base)
# and assigns to a base-class-typed variable. That fails to compile:
#   CS1061: interface has no HandleDataChunking
#   CS0266: cannot implicitly convert interface -> base class
# The concrete plugins derive from the *_Base classes, so an explicit downcast is
# safe and matches the framework's design. Idempotent.
import sys

PATH = "TeamServer/Plugin_BaseClasses/ExtImplantHandleComms_Base.cs"
EDITS = [
    ("var extImplant_TaskPostProcess_Base = PluginService.GetImpPostProcPlugin(implant.ImplantType);",
     "var extImplant_TaskPostProcess_Base = (ExtImplant_TaskPostProcess_Base)PluginService.GetImpPostProcPlugin(implant.ImplantType);"),
    ("ExtImplant_TaskPreProcess_Base extImplant_TaskPreProcess_Base = taskPre_plugin.Value;",
     "ExtImplant_TaskPreProcess_Base extImplant_TaskPreProcess_Base = (ExtImplant_TaskPreProcess_Base)taskPre_plugin.Value;"),
]

path = sys.argv[1] if len(sys.argv) > 1 else PATH
s = open(path).read()
done = 0
for old, new in EDITS:
    if new in s:
        done += 1
        continue
    if old not in s:
        print("PATCH-MISS: pattern not found in %s:\n  %s" % (path, old), file=sys.stderr)
        sys.exit(2)
    s = s.replace(old, new)
    done += 1
open(path, "w").write(s)
print("patched %d/2 casts" % done)
