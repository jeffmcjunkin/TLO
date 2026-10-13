#!/usr/bin/env python3
# Contains HardHatC2 source fragments; Copyright (c) 2023 Jonathan Owens.
# Modifications (July 2026): GPL-3.0-or-later; see COPYING.GPL-3.0 in the deployment
# or LICENSE in the source role. No warranty; retain the original notice below.
# BSD 3-Clause License
#
# Copyright (c) 2023, Jonathan Owens
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# 3. Neither the name of the copyright holder nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
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
