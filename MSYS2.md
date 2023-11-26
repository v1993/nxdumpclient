# Remarks for those brave and foolish enough to try and build in MSYS2 environment

**Building in MSYS2 is currently not officially supported. Please do not open issues if it does not work. Creating a redistributable package is a task on its own.**

## Use UCRT64 environment

It will give you the sanest results overall. CLANG64 also should work.

Install *everything* but stuff like `git` with the environment-specific prefix. This includes meson and python!

## Set environment variable `PYTHONUTF8=1`

Otherwise, `blueprint-compiler` will fail with `UnicodeDecodeError`.