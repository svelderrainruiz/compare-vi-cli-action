## Package layout highlights

- Fixture version `1.4.1.948` (system `1.4.1.948`), license `MIT`.
- Fixture path: `tests\fixtures\icon-editor\ni_icon_editor-1.4.1.948.vip`
- Package smoke status: **fail** (VIPs: 1)
- Report generated: `11/3/2025 10:14:02 PM`
- Artifacts:
  - ni_icon_editor-1.4.1.948.vip - 0.35 MB (`919104d1e35405e40862776f853cc6b9c23b87121d4b717fcbd06742e937e75e`)
  - ni_icon_editor_system-1.4.1.948.vip - 0.28 MB (`8181b37939ed27faa0fdf5f87c881e1cc0b2fe4edecee4384a10c04b9b9af03a`)
  - lv_icon_x64.lvlibp - 2.85 MB (`38c48a463db3735fedcf59cc7aee4022214392d97b51d892c01a9d7ff2d3abf0`)
  - lv_icon_x86.lvlibp - 2.85 MB (`1092bc553474f43a77630713f06a0fad79fa72055ca074d7380c1c07fec31710`)

## Stakeholder summary

- Smoke status: **fail**
- Runner dependencies: mismatch
- Custom actions: 4 entries (all match: False)
- Fixture-only assets discovered: 313

## Comparison with repository sources

- Custom action hashes:
| Action | Fixture Hash | Repo Hash | Match |
| --- | --- | --- | --- |
| VIP_Pre-Install Custom Action 2021.vi | `_missing_` | `05ddb5a2995124712e31651ed4a623e0e43044435ff7af62c24a65fbe2a5273a` | mismatch |
| VIP_Post-Install Custom Action 2021.vi | `_missing_` | `29b4aec05c38707975a4d6447daab8eea6c59fcf0cde45f899f8807b11cd475e` | mismatch |
| VIP_Pre-Uninstall Custom Action 2021.vi | `_missing_` | `a10234da4dfe23b87f6e7a25f3f74ae30751193928d5700a628593f1120a5a91` | mismatch |
| VIP_Post-Uninstall Custom Action 2021.vi | `_missing_` | `958b253a321fec8e65805195b1e52cda2fd509823d0ad18b29ae341513d4615b` | mismatch |

- Runner dependencies hash match: mismatch

## Fixture-only assets

- resource (313 entries)
  - plugins\lv_icon_x64.lvlibp (38c48a463db3735fedcf59cc7aee4022214392d97b51d892c01a9d7ff2d3abf0)
  - plugins\lv_icon_x86.lvlibp (1092bc553474f43a77630713f06a0fad79fa72055ca074d7380c1c07fec31710)
  - plugins\lv_icon.vi (af6be82644d7b0d9252bb5188847a161c641653a38f664bddcacc75bbc6b0b51)
  - plugins\lv_icon.vit (c74159e8f4e16d1881359dae205e71fdee6131020c7c735440697138eec0c0dd)
  - plugins\lv_IconEditor.lvlib (a2721f0b8aea3c32a00d0b148f24bdeee05201b41cffbaa212dbe325fdd4f3f7)
  - ... 308 more

## Fixture-only manifest delta

- Added: 313, Removed: 313, Changed: 0
- Added:
  - `resource:tests\plugins\niiconeditor\miscellaneous\ni.com_iconlibrary\get http.vi`
  - `resource:tests\plugins\niiconeditor\class\tools\eraser.vi`
  - `resource:tests\plugins\niiconeditor\controls\references.ctl`
  - `resource:tests\plugins\niiconeditor\controls\tools.ctl`
  - `resource:tests\plugins\niiconeditor\support\defaulticonglyphdata.vi`
  - (+308 more)
- Removed:
  - `resource:resource\plugins\lv_icon_x64.lvlibp`
  - `resource:resource\plugins\lv_icon_x86.lvlibp`
  - `resource:resource\plugins\lv_icon.vi`
  - `resource:resource\plugins\lv_icon.vit`
  - `resource:resource\plugins\lv_iconeditor.lvlib`
  - (+308 more)

## Changed VI comparison (requests)

- When changed VI assets are detected, Validate publishes an 'icon-editor-fixture-vi-diff-requests' artifact
  with the list of base/head paths for LVCompare.
- Local runs can generate requests via tools/icon-editor/Prepare-FixtureViDiffs.ps1.

## Simulation metadata

- Simulation enabled: True
- Unit tests executed: False
