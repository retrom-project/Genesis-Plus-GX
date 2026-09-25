# Retrom Genesis Plus GX core

Develop Retrom changes on `fix/*`, `feat/*` or `build/*` branches from `retrom/g63f0c6870601`. Keep `master` as the upstream mirror. The fork owns the browser core build and candidate assets; `retrom-fork.json` fixes the upstream source and linker commits. Run `.github/rpg-runtime/build-candidate.sh` with an absolute empty output directory under the named PFB. Do not commit game content, BIOS, toolchains or built core assets.

For CHD content, the core reads ordinary files through EmulatorJS's shared filesystem. The retrom-runtime Content I/O mount provides seekable reads, caching, validation, and cancellation at that filesystem boundary. Do not add a Genesis Plus GX specific range callback or download path. Keep local file paths working for other Genesis Plus GX platforms.
