## Package layout highlights

- Fixture version `1.4.1.948` (system `1.4.1.948`), license `MIT`.
- Fixture path: `tests\fixtures\icon-editor\ni_icon_editor-1.4.1.948.vip`
- Package smoke status: **ok** (VIPs: 1)
- Report generated: `11/2/2025 8:38:27 PM`
- Artifacts:
  - ni_icon_editor-1.4.1.948.vip - 28.12 MB (`ed48a629e7fe5256dcb04cf3288a6e42fe8c8996dc33c4d838f8b102b43a9e44`)
  - ni_icon_editor_system-1.4.1.948.vip - 28.03 MB (`534ff97b24f608ac79997169eca9616ab2c72014cc9c9ea9955ee7fb3c5493c2`)
  - lv_icon_x64.lvlibp - 2.85 MB (`e851ac8d296e78f4ed1fd66af576c50ae5ff48caf18775ac3d4085c29d4bd013`)
  - lv_icon_x86.lvlibp - 2.85 MB (`8a3d07791c5f03d11bddfb32d25fd5d7c933a2950d96b5668cc5837fe7dece23`)

## Stakeholder summary

- Smoke status: **ok**
- Runner dependencies: match
- Custom actions: 4 entries (all match: False)
- Fixture-only assets discovered: 335

## Comparison with repository sources

- Custom action hashes:
| Action | Fixture Hash | Repo Hash | Match |
| --- | --- | --- | --- |
| VIP_Pre-Install Custom Action 2021.vi | `05ddb5a2995124712e31651ed4a623e0e43044435ff7af62c24a65fbe2a5273a` | `_missing_` | mismatch |
| VIP_Post-Install Custom Action 2021.vi | `29b4aec05c38707975a4d6447daab8eea6c59fcf0cde45f899f8807b11cd475e` | `_missing_` | mismatch |
| VIP_Pre-Uninstall Custom Action 2021.vi | `a10234da4dfe23b87f6e7a25f3f74ae30751193928d5700a628593f1120a5a91` | `_missing_` | mismatch |
| VIP_Post-Uninstall Custom Action 2021.vi | `958b253a321fec8e65805195b1e52cda2fd509823d0ad18b29ae341513d4615b` | `_missing_` | mismatch |

- Runner dependencies hash match: match

## Fixture-only assets

- resource (311 entries)
  - plugins\lv_icon.vi (af6be82644d7b0d9252bb5188847a161c641653a38f664bddcacc75bbc6b0b51)
  - plugins\lv_icon.vit (c74159e8f4e16d1881359dae205e71fdee6131020c7c735440697138eec0c0dd)
  - plugins\lv_IconEditor.lvlib (a2721f0b8aea3c32a00d0b148f24bdeee05201b41cffbaa212dbe325fdd4f3f7)
  - plugins\NIIconEditor\Class\Ants\Ants.lvclass (650baef4cded7115e549f0f99258884c43185f88b6a082b1629e0fa72406f176)
  - plugins\NIIconEditor\Class\Ants\GET\GET_AntsLine.vi (794dfcbf2ed7ff560f2346ba51c840d00dc22e58098c9f4a76cdeb370b9c9df9)
  - ... 306 more
- script (1 entries)
  - update_readme_hours.py (7f5bbfadb1193a89f1a4aa6332ccf62650951d389edb2188d86e1e29442049c4)
- test (23 entries)
  - Unit Tests\Editor Position\Adjust Position.vi (7b14873d4a25688c5f78c40ffa547b93836a04661fbeeeddb426268fcd192dbb)
  - Unit Tests\Editor Position\Assert Windows Bounds.vi (8eb3bdbc13edaa58df1d3f9ad8d005c24cdae6ee2178bc9b099dc9781e69d7ca)
  - Unit Tests\Editor Position\Backup INI Data.vi (da527567a1c21e2c3bb89c28e315ae22ae4202323d28f4bc302ca56113a7e48b)
  - Unit Tests\Editor Position\Editor Position.lvclass (58ea81ddcd56be9a0aaa74a50684270d0c6c624fbde9ab538416ed87ae7321d8)
  - Unit Tests\Editor Position\INI Position Removed.vi (62872f3cc37348238d71d3c5ecb64bc7f0d93e62a3ec0e24b3137f9d6a5b391d)
  - ... 18 more

## Fixture-only manifest delta

- Added: 311, Removed: 0, Changed: 0
- Added:
  - `resource:tests\plugins\niiconeditor\miscellaneous\icon editor\get icon editor context.vi`
  - `resource:tests\plugins\niiconeditor\controls\settings.ctl`
  - `resource:tests\plugins\niiconeditor\controls\arrow up.ctl`
  - `resource:tests\plugins\niiconeditor\miscellaneous\icon editor\mouse down_glyphs.vi`
  - `resource:tests\plugins\niiconeditor\miscellaneous\tools\selection_setnewdata.vi`
  - (+306 more)

## Changed VI comparison (requests)

- When changed VI assets are detected, Validate publishes an 'icon-editor-fixture-vi-diff-requests' artifact
  with the list of base/head paths for LVCompare.
- Local runs can generate requests via tools/icon-editor/Prepare-FixtureViDiffs.ps1.

## Simulation metadata

- Simulation enabled: True
- Unit tests executed: False
