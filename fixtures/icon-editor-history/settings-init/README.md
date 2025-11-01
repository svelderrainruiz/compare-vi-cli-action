Icon editor fixture for history tests (issue #531).

The files in `commits/` mirror simplified snapshots of
`resource/plugins/NIIconEditor/Miscellaneous/Settings Init.vi`.
They are plain text stand ins that let the unit tests build a synthetic
repository with divergent history (including a merge commit) without
pulling the real LabVIEW sources.

