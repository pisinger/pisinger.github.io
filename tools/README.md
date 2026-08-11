# PS, Here’s What I Learned

Jekyll source for [pisinger.github.io](https://pisinger.github.io), a blog about Microsoft cloud, security, automation, and related topics.

## Prerequisites

- Ruby
- Bundler

On Ubuntu or WSL, install them with:

```bash
sudo apt update
sudo apt install ruby-full build-essential
sudo gem install bundler
```

## Install dependencies

From the repository root:

```bash
bundle config set --local path vendor/bundle
bundle install
```

The gems are installed into the ignored `vendor/bundle` directory.

## Run the site locally

Start the development server with file watching:

```bash
bundle exec jekyll serve --host 127.0.0.1 --port 4000 --watch
```

Open <http://127.0.0.1:4000> in a browser. Press `Ctrl+C` to stop the server.

To make the site reachable from another host or container, bind it to all interfaces:

```bash
bundle exec jekyll serve --host 0.0.0.0 --port 4000 --watch
```

The repository helper also starts Jekyll with LiveReload:

```bash
bash tools/run.sh
```

If the LiveReload port is already occupied, use the direct command above without `--livereload`.

## Build and validate

Build the site into `_site` and run HTML-Proofer validation:

```bash
bash tools/test.sh
```

The script builds the production version and checks internal links, anchors, images, and scripts. A successful run ends with `HTML-Proofer finished successfully.`

To build without validation:

```bash
bundle exec jekyll build --destination _site
```

The `_site` directory is generated output and should not be committed.

## Content locations

- `_posts/` — blog posts
- `_tabs/` — About, Contact, Archives, Tags, and other site pages
- `index.html` — curated homepage
- `_data/contact.yml` — sidebar contact links
- `assets/` — images and site assets
- `samples/` — local-only HTML design samples; excluded from the Jekyll build

New posts added to `_posts/` automatically appear in the homepage’s three most recent article cards and in Archives.
