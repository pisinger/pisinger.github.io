# Repo Instructions

This repository is a personal Jekyll blog built on `jekyll-theme-chirpy`. It publishes cloud and security writing, plus a few curated roundup feeds, so agents should expect a mix of normal posts, collection-based content, and theme/layout code.

## Start here

- `README.md` and `docs/README.md` explain the project at a high level.
- `_config.yml` defines the site title, collections, defaults, analytics, and build behavior.
- `_posts/` holds normal blog posts.
- `_ms_tech_news/`, `_ms_release_radar/`, and `_wiz_release_radar/` hold generated or curated roundup content.
- `_tabs/` contains top-level pages shown in the site navigation.
- `_layouts/` and `_includes/` contain the shared theme overrides and page shells.
- `tools/run.sh` runs the site locally; `tools/test.sh` builds and checks the generated site.

## Where to look for common changes

- Post edits: `_posts/` plus the post front matter.
- Roundup edits: the matching collection folder and `_template.md` in that collection.
- Navigation or page content: `_tabs/` and `_data/`.
- Shared UI or metadata changes: `_layouts/`, `_includes/`, and `_config.yml`.
- Images and post assets: `assets/img/posts/` under the matching article slug.

## Working rules

- Keep changes small and aligned with Chirpy conventions.
- Prefer Markdown/front matter changes over theme internals unless the behavior lives in a layout or include.
- If you change templates, config, or shared includes, validate with `tools/test.sh`.
- Do not commit generated site output, caches, or dependency folders.
- Preserve existing permalink and collection patterns unless the task explicitly requires a site-wide change.

## Site identity

- Site title: `PS, Here’s What I Learned 🔐`
- Author: `Pit Singert`
- Theme: `jekyll-theme-chirpy`
