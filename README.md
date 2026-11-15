# PipeTail blog

Hugo site served by GitHub Pages from the `docs/` folder on `master`. No CI builds it: the generated `docs/` is committed.

## Content guidelines

- for the title images always use 1400 x 900

## Publish a new article

1. Create the post: `hugo new posts/YYYY-MM-DD-<slug>.md`, and put its images in `content/images/`, named `YYYY-MM-DD-<slug>-title.jpg`.
2. Preview locally: `make serve` (drafts included), then open http://localhost:1313.
3. Set `draft: false` in the post front matter.
4. Generate the public assets: `make build` (runs `hugo --destination docs`).
5. Commit the post and the regenerated `docs/` together, open a PR, and merge it to `master`.
6. GitHub Pages deploys `docs/` within a few minutes. Check https://blog.pipetail.io.
