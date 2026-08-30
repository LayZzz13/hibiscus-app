# Hibiscus website

This directory contains the static Hibiscus project website. It has no build step or runtime dependencies.

Preview it locally from the repository root:

```sh
cd Website
python3 -m http.server 8000
```

Then open <http://localhost:8000/>.

When a TestFlight or App Store destination is available, update `downloadLabel` and `downloadURL` in `site-config.js`.

The App Store screenshots in `assets/screenshots/` are the supplied final marketing artwork. The first page from the source set is intentionally omitted.
