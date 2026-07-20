# Shelfworth landing page

Everything in this directory is deployed as-is to GitHub Pages at
**https://ikidd42.github.io/shelfworth/** whenever `site/**` changes on `main`
(see `.github/workflows/pages.yml`).

Ground rules for the site:

- Static only — plain HTML/CSS (and minimal JS if truly needed). No build
  step, no frameworks; whatever is in this folder is served verbatim, with
  `index.html` as the entry point.
- Match the app's Athenaeum design language: ivory paper `#F6F0E4`, ink
  `#2A2115`, library green `#31553B`, brass `#9A701F`, serif display type,
  dark mode as "reading by lamplight" (`#151009` canvas). The placeholder
  `index.html` carries the palette as CSS variables for both modes.
- Assets: app screenshots live in `../docs/screenshots/`; the icon and
  marbled sheets can be regenerated with `swift ../tools/generate_icon.swift`.
  The site's own marbled hero panels and endpaper backdrops are rendered by
  `swift ../tools/generate_site_assets.swift` into `assets/`.
  Copy what you need into this folder rather than referencing outside it.
