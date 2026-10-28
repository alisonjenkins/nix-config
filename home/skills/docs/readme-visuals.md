# README visuals

## When a visual earns its place

Include a visual only if it shows something prose cannot, such as a user interface, a terminal session, or an architecture flow. Evidence is correlational: Venigalla and Chimalakonda 2022 studied 1,950 READMEs and found image count was a top-3 feature in 8 of 10 languages. The study does not show that images cause popularity.

Order elements carefully on the first screen. Place the project name first, followed by the one-line pitch, and place at most one image above the pitch (see [readme.md](readme.md)).

## Choosing a format

| Need | Use | Notes |
|---|---|---|
| Architecture or flow | Fenced mermaid block committed as source | GitHub renders mermaid, geojson, topojson and ascii STL in fenced blocks. GitHub documents no size limit, dark-mode behaviour or accessibility behaviour for them; it only says to check the Mermaid version in use. Rendering outside GitHub (npm, PyPI, crates.io) is unverified, so keep a text description beside it. |
| CLI session | VHS .tape file plus a generated GIF | See CLI demos. |
| Terminal output that does not move | Fenced text block, not a screenshot | Google docguide prefers text so it can be searched and copied. |
| GUI | PNG screenshot | See Screenshots. |
| Logo | SVG | See Logos. |

## Diagrams

Commit the diagram source, not only the generated image. This ensures diagrams remain maintainable in version control.

For C4 diagrams, follow the checklist requirements: provide a title, a legend, and a label on every arrow (https://c4model.com/diagrams/checklist). Add alt text or a prose summary for any diagram so readers can understand it without rendering.

## Screenshots (GUI)

Follow GitHub's docs style guide for interface captures: use PNG, 750 to 1000 px wide, and 250 KB or less. Crop tightly to the relevant area.

GitHub limits attachments to 10MB for images and gifs, 10MB for videos in a repository of a free plan (100MB on a paid plan), and 25MB for all other files. These are attachment limits. Pushed files: Git warns above 50 MiB, GitHub blocks above 100 MiB, and files added in the browser can be at most 25 MiB. Store screenshots inside the repository (docs/images/ or assets/) so they version with the code.

Regenerating screenshots in CI using tools such as Playwright or shot-scraper (if present) needs a pinned browser or runner, contents: write permission to commit the result, and a paths: filter so it runs only when the interface changes. This is a pattern from tool docs, not a standard.

## CLI demos

Use VHS (if present) to record a terminal session from a .tape script; VHS README documents GIF, MP4, WebM, a PNG frame sequence and txt/ascii output (WebP and SVG are not listed). The charmbracelet/vhs-action GitHub Action can regenerate the visual in CI.

Asciinema recordings are JSON cast files. GitHub strips the asciinema script player from rendered README files; asciinema docs confirm the preview is an SVG, useful "where <script> tags are not allowed", such as a README on GitHub; snippet `[![asciicast](https://asciinema.org/a/<id>.svg)](https://asciinema.org/a/<id>)`.

Keep a terminal demo under about 30 seconds and demonstrate one task (judgement, not sourced). WCAG 2.2.2 (pause, stop, hide) and 2.3.1 (three flashes) apply to animated GIFs. GIFs cannot be paused, so keep them short and flash-free, and explain what they show in surrounding text.

## GIF, MP4 or WebP

Resolve the format trade-off before committing. Google docguide suggests video formats such as MP4 over GIF to reduce payload size. Testing with GitHub's Markdown render API confirms `<video>` and `<source>` tags are stripped to an empty paragraph, a bare .mp4 URL becomes a plain link, and `![x](demo.mp4)` becomes an `<img>` tag rather than a video element. A committed .mp4 does not embed in a README; the documented route is a video attachment (supported types .mp4, .mov, .webm). Keep GIF as the default for a short README demo.

GitHub's "Attaching files" page lists PNG, GIF, JPEG, SVG and video (.mp4, .mov, .webm), plus BMP and TIFF in issues and PRs. WebP and AVIF appear nowhere on that page. GitHub's render API keeps both WebP and AVIF as `<img>` tags (the renderer accepts them, though display in the browser was not tested and neither is in GitHub's documented list). crates.io treats webp as media and does not list avif. VHS does not output WebP directly, so convert using gif2webp or img2webp if present. Browser support for WebP is about 97%.

Default to GIF from VHS for a short CLI demo and PNG for screenshots; a video attachment is the documented route for longer ones. Use WebP only after checking that it renders in the target host. Do not rely on AVIF.

## Dark mode

Prefer a <picture> element with dark and light image sources over the #gh-dark-mode-only and #gh-light-mode-only URL fragments. GitHub's render API confirms `<picture>` with `<source media="(prefers-color-scheme: dark)">` survives wrapped in a `<themed-picture>` element, which supports the recipe. The `#gh-dark-mode-only` fragment is kept verbatim in the image src by the renderer. The current GitHub docs do not mention the fragment and carry no deprecation note, nor does the 2021 changelog entry; whether the web UI still honours it is unverified. Prefer `<picture>`.

```html
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="dark.png">
  <img alt="Project overview" src="light.png">
</picture>
```

Use absolute URLs in the <picture> element for any README published to registries such as npm or PyPI; crates.io resolves relative URLs against the repository field on github.com, gitlab.com or bitbucket.org, but npm and PyPI show no such handling.

## Logos

Logos are optional. Popular libraries such as requests and commander.js do not have one.

If you include a logo, use a transparent SVG in a <picture> pair for dark mode. Keep the pitch directly under it and place at most one image above the pitch. No source gives a standard logo width.

Forks of a project must not reuse the original project's trademarked logo without permission (caution, not legal advice).

## Accessibility checklist

- [ ] Every image has alt text that says what it shows.
- [ ] No critical information exists only in an image.
- [ ] Animated content is short and flash-free.
- [ ] Contrast holds in both light and dark mode.

## Sources and confidence

| Source | URL |
|---|---|
| GitHub supported diagrams | https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/creating-diagrams |
| GitHub docs style guide images | https://docs.github.com/en/contributing/writing-for-github-docs/creating-screenshots |
| GitHub large files | https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github |
| GitHub attaching files | https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/attaching-files |
| GitHub changelog theme context | https://github.blog/changelog/2022-05-19-specify-theme-context-for-images-in-markdown/ |
| GitHub dark mode blog | https://github.blog/developer-skills/github/how-to-make-your-images-in-markdown-on-github-adjust-for-dark-mode-and-light-mode/ |
| VHS | https://github.com/charmbracelet/vhs |
| vhs-action | https://github.com/charmbracelet/vhs-action |
| asciinema | https://docs.asciinema.org/ |
| asciinema embedding | https://docs.asciinema.org/manual/server/embedding/ |
| WCAG 2.2 | https://www.w3.org/TR/WCAG22/ |
| C4 checklist | https://c4model.com/diagrams/checklist |
| Google docguide | https://google.github.io/styleguide/docguide/best_practices.html |
| Venigalla and Chimalakonda 2022 | (cite by author and year) |

Confidence: checked by running the tool or reading source on 2026-10-28. Remaining unverified: whether the web UI still honours #gh-dark-mode-only; WebP/AVIF display on GitHub; PyPI and npm relative-link handling; logo evidence is correlational; Venigalla and Chimalakonda not re-fetched.
