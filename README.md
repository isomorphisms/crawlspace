# Crawl Space

Get underneath Android without making every program privileged.

Crawl Space is a small bridge between an ordinary Android app/terminal process and a process launched with Android's `shell` (or later `root`) identity.

The first target is the MIRO A1 on Android 14. The immediate use case is running tools such as `tmovvm`, which need Android system access unavailable to ordinary Termux.

The design rule is narrow privilege: keep normal programs normal, and put the smallest possible interface across the privilege boundary.
