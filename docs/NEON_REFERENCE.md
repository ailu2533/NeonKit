# neon Reference Mapping

This repository vendors `neon` as a submodule at `Vendor/neon` and does not modify upstream sources.

Reference version:
- base tag `0.36.0`
- pinned commit `a2e24780142140c06c5ac63014f80457bb0e7121`
  (includes upstream test fix for `test/basic.c:getbuf_retry`)

All Swift wrappers in `NeonRaw` and `NeonKit` are layered on top of this fixed version.
