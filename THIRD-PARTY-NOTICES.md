# Third-party notices

Tormenta Imperial is licensed under the terms in [`LICENSE`](LICENSE) (PolyForm
Strict 1.0.0 for the source code; all rights reserved for the original art, text
and the name).

**Those terms do not apply to the components listed here.** Each keeps its own
licence, granted by its own authors. Nothing in `LICENSE` restricts your rights
to these components, and nothing here grants you rights to the rest of the game.

This file covers what is **actually shipped** in the builds handed to players:

- **Windows** — `TormentaImperial.exe`: the official Godot 4.7 (.NET/mono) Windows
  export template with the game data embedded in it.
- **Android** — `TormentaImperial-*.apk`: the official Godot 4.7 Android export
  template (arm64-v8a), its Java/Kotlin runtime libraries, and the game data.

Each release zip carries this file, `LICENSE`, `GODOT-COPYRIGHT.txt` and the font
licence files listed in §3.

> **No .NET runtime is shipped.** The project has no C# code (no `.csproj`, no
> `.cs`). The Windows export produces no `data_TormentaImperial_*` folder and no
> assemblies, and the APK contains no `.dll` or .NET runtime. The mono export
> template only contains Godot's own (MIT) glue code for C#, which stays unused.

---

## 1. Godot Engine

| Component | Version | Licence |
|---|---|---|
| [Godot Engine](https://godotengine.org) | 4.7-stable (official, build `5b4e0cb0f`) | MIT (Expat) — full text in [Appendix A](#appendix-a--godot-engine-mit-licence) |

Godot includes third-party libraries, each under its own licence. Their complete
copyright notices and the **full text of every licence below** are in
[`licenses/GODOT-COPYRIGHT.txt`](licenses/GODOT-COPYRIGHT.txt) (shipped in each
zip as `GODOT-COPYRIGHT.txt`). That file is generated from the engine binary itself
by `tools/gen_godot_notices.gd` and matches Godot's own
[`COPYRIGHT.txt`](https://github.com/godotengine/godot/blob/5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88/COPYRIGHT.txt).
The list is for the whole engine; each export template compiles in a subset of it
(for example, no Wayland code on Windows and no Direct3D code on Android).

| Component (inside Godot) | Licence |
|---|---|
| Bullet Continuous Collision Detection and Physics Library | Expat and Zlib |
| Linux AppStream Metadata File | CC0-1.0 |
| Godot Engine logo | CC-BY-4.0 |
| Betsy | Expat |
| Chipmunk2D Joint Constraints | Expat |
| Open Dynamics Engine | BSD-3-clause |
| Jolt Physics | Expat |
| Joint Non-Local Means (JNLM) denoiser | Expat |
| The Android Open Source Project | Apache-2.0 |
| ProcessPhoenix | Apache-2.0 |
| Robert Penner's Easing Functions | Expat |
| NVidia's FXAA 3.11, simplified by Simon Rodriguez | BSD-3-clause and Expat |
| Intel ASSAO and related files | Expat |
| Temporal Anti-Aliasing resolve implementation | Expat |
| Subpixel Morphological Antialiasing | Expat |
| AccessKit | Expat |
| AMD FidelityFX Super Resolution | Expat |
| AMD FidelityFX Super Resolution 2 | Expat |
| ANGLE | BSD-3-clause |
| Arm ASTC Encoder | Apache-2.0 |
| Basis Universal | Apache-2.0 |
| Brotli | Expat |
| CA certificates | MPL-2.0 |
| Clipper2 | BSL-1.0 |
| Convection Texture Tools Stand-Alone Kernels | Expat |
| D3D12 Memory Allocator | Expat |
| DirectX Headers | Expat |
| doctest | Expat |
| dr_libs | Unlicense or MIT-0 |
| Embree | Apache-2.0 |
| ENet | Expat |
| etcpak | BSD-3-clause |
| DroidSans font | Apache-2.0 |
| Inter font | OFL-1.1 |
| JetBrains Mono font | OFL-1.1 |
| Noto Sans font | OFL-1.1 |
| Open Sans font | OFL-1.1 |
| Vazirmatn font | OFL-1.1 |
| The FreeType Project | FTL |
| GamepadMotionHelpers | Expat |
| glad | CC0-1.0 and Apache-2.0 |
| glslang | glslang |
| Graphite engine | Expat |
| Grisu2 float serialization algorithm | Expat and Apache-2.0 |
| HarfBuzz text shaping library | HarfBuzz |
| International Components for Unicode | Unicode |
| libbacktrace | BSD-3-clause |
| libjpeg-turbo | BSD-3-clause and IJG |
| KTX | Apache-2.0 |
| OggVorbis | BSD-3-clause |
| libpng | Zlib |
| OggTheora | BSD-3-clause |
| WebP codec | BSD-3-clause |
| Manifold | Apache-2.0 |
| Mbed TLS | Apache-2.0 |
| meshoptimizer | Expat |
| metal-cpp | Apache-2.0 |
| mingw-std-threads | BSD-2-clause |
| MiniUPnP Project | BSD-3-clause |
| MiniZip | Zlib |
| bcdec | Expat |
| Fast Filtering of Reflection Probes | Expat |
| FastLZ | Expat |
| FastNoise Lite | Expat |
| libjingle | BSD-3-clause |
| Tangent Space Normal Maps implementation | Zlib |
| NVIDIA NVAPI (minimal excerpt) | Expat |
| OK Lab color space | Expat |
| Minimal PCG32 implementation | Apache-2.0 |
| PolyPartition / Triangulator | Expat |
| Quite OK Audio Format | Expat |
| r128 library | Unlicense |
| SMAZ | BSD-3-clause |
| SMOL-V | Unlicense or Expat |
| stb libraries | Unlicense or Expat |
| YUV2RGB | BSD-2-clause |
| Multi-channel signed distance field generator | Expat |
| OpenXR Loader | Apache-2.0 |
| PCRE2 | BSD-3-clause |
| Recast | Zlib |
| RVO2 | Apache-2.0 |
| SDL | Zlib |
| hidapi | BSD-3-clause |
| SPIRV-Cross | Apache-2.0 or Expat |
| SPIRV-Headers | Expat |
| SPIRV-Reflect | Apache-2.0 |
| Swappy | Apache-2.0 |
| ThorVG | Expat |
| TinyEXR | BSD-3-clause |
| ufbx | Expat |
| V-HACD | BSD-3-clause |
| volk | Expat |
| Vulkan Headers | Apache-2.0 |
| Vulkan Memory Allocator | Expat |
| Wayland core protocol | Expat |
| Wayland protocols | Expat |
| Mesa Wayland protocols | X11 |
| Wslay | Expat |
| xatlas | Expat |
| zlib | Zlib |
| Zstandard | BSD-3-clause |

"Expat" is the MIT licence. Godot's boot splash is replaced by the game's own logo,
so the Godot logo (CC-BY-4.0) is not displayed by the game.

## 2. Android runtime libraries (APK only)

Bundled by Godot's Android export template. All are licensed under the Apache
License 2.0 ([Appendix B](#appendix-b--apache-license-20)).

| Component | Copyright | Licence |
|---|---|---|
| AndroidX libraries (`androidx.core`, `activity`, `fragment`, `lifecycle`, `collection`, `annotation`, `startup`, `profileinstaller`, `documentfile`, ...) | The Android Open Source Project | Apache 2.0 |
| Kotlin standard library | JetBrains s.r.o. and Kotlin Programming Language contributors | Apache 2.0 |
| kotlinx.coroutines | JetBrains s.r.o. and Kotlin Programming Language contributors | Apache 2.0 |
| JetBrains Java Annotations | JetBrains s.r.o. | Apache 2.0 |
| LLVM libc++ (`libc++_shared.so`, from the Android NDK) | LLVM Project contributors | Apache 2.0 with LLVM Exceptions — <https://llvm.org/LICENSE.txt> |

## 3. Fonts (`assets/fonts/`)

Embedded in the game data. Each licence file ships next to the font in the
repository and inside every release zip (folder `licenses/fonts/`).

| Font | Copyright | Licence | Licence file |
|---|---|---|---|
| Special Elite | © 2010 Brian J. Bonislawsky DBA Astigmatic (AOETI) | Apache License 2.0 ([Appendix B](#appendix-b--apache-license-20)) | `assets/fonts/LICENSE-SpecialElite.txt` |
| Caveat | © 2014 The Caveat Project Authors | SIL Open Font License 1.1 ([Appendix C](#appendix-c--sil-open-font-license-11)) | `assets/fonts/OFL-Caveat.txt` |
| Black Ops One | © 2022 The Black-Ops Project Authors | SIL Open Font License 1.1 | `assets/fonts/OFL-BlackOpsOne.txt` |
| Rajdhani (Medium, SemiBold, Bold) | © 2014 Indian Type Foundry | SIL Open Font License 1.1 | `assets/fonts/OFL-Rajdhani.txt` |

The OFL permits embedding these fonts in this game. The font files themselves
remain under the OFL and may not be sold on their own. All four fonts are
distributed unmodified. Source: Google Fonts.

## 4. Audio (`assets/audio/`)

All music and sound effects are **CC0 1.0** (public-domain dedication, no
conditions). Credited anyway; per-clip detail in [`assets/CREDITS.md`](assets/CREDITS.md).

| Clips | Source | Licence |
|---|---|---|
| `music/era_1_frontier`, `era_2_industrial`, `era_3_petroleum`, `victory` | [Dark Sci-Fi Audio Pack](https://opengameart.org/content/dark-sci-fi-audio-pack) by SRG774 (OpenGameArt) | CC0 1.0 |
| `sfx/build_place`, `demolish`, `process_done`, `mining_done` | [Kenney — Impact Sounds](https://kenney.nl/assets/impact-sounds) | CC0 1.0 |
| `sfx/build_complete`, `unlock`, `event_positive`, `event_danger`, `insufficient`, `ui_click` | [Kenney — Interface Sounds](https://kenney.nl/assets/interface-sounds) | CC0 1.0 |
| `sfx/upgrade_complete`, `era_up`, `milestone` | [Kenney — Music Jingles](https://kenney.nl/assets/music-jingles) | CC0 1.0 |
| `sfx/trade_buy`, `trade_sell`, `unit_ready` | [Kenney — RPG Audio](https://kenney.nl/assets/rpg-audio) | CC0 1.0 |

## 5. Textures (`assets/textures/`)

| Files | Source | Licence |
|---|---|---|
| `metal_plate_diff_1k`, `metal_plate_nor_gl_1k`, `metal_plate_rough_1k` | [Poly Haven — Metal Plate](https://polyhaven.com/a/metal_plate) | CC0 1.0 |
| `ui/panel_metal`, `ui/panel_inset_metal`, `ui/button_metal` | Derived from the Poly Haven texture above by `tools/gen_ui_textures.gd` | CC0 1.0 (source); the derived sprites are part of the game's art |

## 6. Original content (not third-party)

Made for this game by its author and covered by `LICENSE` (all rights reserved):
the building 3D models in `assets/models/` (built in Blender with the scripts in
`tools/`), the resource and unit icons in `assets/textures/ui/icons/` and
`assets/textures/ui/units/` (drawn by `tools/gen_resource_icons.gd` and
`tools/gen_unit_icons.gd`), the logo, banner, key art and app icon
(`assets/branding/`, `icon.svg`), and all game text.

## 7. Development tools (not shipped)

These addons live in the repository for development only. Both export presets
exclude them (`addons/gdUnit4/*`, `addons/beckett/*` in `export_presets.cfg`, checked
by `tests/build/test_export_guards.gd`), so no file of theirs is in any build.

| Component | Version | Licence | Licence file |
|---|---|---|---|
| [gdUnit4](https://github.com/godot-gdunit-labs/gdUnit4) — unit testing framework | 6.2.1 | MIT © 2023 Mike Schulze | `addons/gdUnit4/LICENSE` |
| [Beckett — MCP for Godot](https://github.com/beckettlab/beckett-godot-mcp) — editor automation | 1.14.0 | MIT © 2026 Beckett | `addons/beckett/LICENSE` |

---

If you believe something here is listed incorrectly, or a component is missing,
please open an issue at <https://github.com/bryansank/tormenta-imperial/issues>.

---

## Appendix A — Godot Engine MIT licence

```text
Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md).
Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Appendix B — Apache License 2.0

Applies to Special Elite and to the Android runtime libraries in §2 (and to the
Godot components marked Apache-2.0, whose notices are in `GODOT-COPYRIGHT.txt`).

```text
                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

   APPENDIX: How to apply the Apache License to your work.

      To apply the Apache License to your work, attach the following
      boilerplate notice, with the fields enclosed by brackets "[]"
      replaced with your own identifying information. (Don't include
      the brackets!)  The text should be enclosed in the appropriate
      comment syntax for the file format. We also recommend that a
      file or class name and description of purpose be included on the
      same "printed page" as the copyright notice for easier
      identification within third-party archives.

   Copyright [yyyy] [name of copyright owner]

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
```

## Appendix C — SIL Open Font License 1.1

Applies to Caveat, Black Ops One and Rajdhani. Each font's copyright line is at
the top of its own licence file (§3).

```text
-----------------------------------------------------------
SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007
-----------------------------------------------------------

PREAMBLE
The goals of the Open Font License (OFL) are to stimulate worldwide
development of collaborative font projects, to support the font creation
efforts of academic and linguistic communities, and to provide a free and
open framework in which fonts may be shared and improved in partnership
with others.

The OFL allows the licensed fonts to be used, studied, modified and
redistributed freely as long as they are not sold by themselves. The
fonts, including any derivative works, can be bundled, embedded, 
redistributed and/or sold with any software provided that any reserved
names are not used by derivative works. The fonts and derivatives,
however, cannot be released under any other type of license. The
requirement for fonts to remain under this license does not apply
to any document created using the fonts or their derivatives.

DEFINITIONS
"Font Software" refers to the set of files released by the Copyright
Holder(s) under this license and clearly marked as such. This may
include source files, build scripts and documentation.

"Reserved Font Name" refers to any names specified as such after the
copyright statement(s).

"Original Version" refers to the collection of Font Software components as
distributed by the Copyright Holder(s).

"Modified Version" refers to any derivative made by adding to, deleting,
or substituting -- in part or in whole -- any of the components of the
Original Version, by changing formats or by porting the Font Software to a
new environment.

"Author" refers to any designer, engineer, programmer, technical
writer or other person who contributed to the Font Software.

PERMISSION & CONDITIONS
Permission is hereby granted, free of charge, to any person obtaining
a copy of the Font Software, to use, study, copy, merge, embed, modify,
redistribute, and sell modified and unmodified copies of the Font
Software, subject to the following conditions:

1) Neither the Font Software nor any of its individual components,
in Original or Modified Versions, may be sold by itself.

2) Original or Modified Versions of the Font Software may be bundled,
redistributed and/or sold with any software, provided that each copy
contains the above copyright notice and this license. These can be
included either as stand-alone text files, human-readable headers or
in the appropriate machine-readable metadata fields within text or
binary files as long as those fields can be easily viewed by the user.

3) No Modified Version of the Font Software may use the Reserved Font
Name(s) unless explicit written permission is granted by the corresponding
Copyright Holder. This restriction only applies to the primary font name as
presented to the users.

4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font
Software shall not be used to promote, endorse or advertise any
Modified Version, except to acknowledge the contribution(s) of the
Copyright Holder(s) and the Author(s) or with their explicit written
permission.

5) The Font Software, modified or unmodified, in part or in whole,
must be distributed entirely under this license, and must not be
distributed under any other license. The requirement for fonts to
remain under this license does not apply to any document created
using the Font Software.

TERMINATION
This license becomes null and void if any of the above conditions are
not met.

DISCLAIMER
THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT
OF COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE
COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL
DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM
OTHER DEALINGS IN THE FONT SOFTWARE.
```
