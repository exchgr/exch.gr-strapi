# exch.gr-strapi

## What It Is
exch.gr-strapi is the [strapi](https://strapi.io/) backend portion ofthe blog hosted at https://exch.gr/. It serves as a headless CMS that hosts all the data for articles, tags, collections, redirects, etc. Then, [exch.gr-11ty](https://github.com/exchgr/exch.gr-11ty) pulls the data and generates the website.

## Upgrading

Toolchain prerequisites:

- `brew bundle` installs the CLI tools in the `Brewfile` (everything required by `scripts/upgrade.sh`).
- node is managed by asdf and pinned in `.tool-versions`.
- yarn upgrades itself via `yarn set version berry`.

The `upgrade` yarn script (`bash scripts/upgrade.sh`) runs the phases selected by the flags below. A hard-fail preflight aborts the run if a required tool is missing, `gh` is not authenticated, or the worktree is dirty.

Run everything with `yarn run upgrade --all`, or select phases piecemeal to control blast radius — flags combine; running with no flags is a usage error.

| Flag | Phase |
| --- | --- |
| `-a`, `--all` | every phase |
| `-y`, `--yarn` | yarn berry + install |
| `-n`, `--node` | asdf node LTS pin + engines rewrite |
| `-d`, `--dependencies` | direct dependency bumps |
| `-t`, `--transitive` | transitive refresh + dedupe |
| `-s`, `--strapi-types` | Strapi type regeneration |
| `-w`, `--workflows` | GitHub Actions action bumps |
| `-i`, `--docker` | Dockerfile base image bumps |
| `-r`, `--dry-run` | print planned mutations without applying them; composes with any selection |
| `-h`, `--help` | show usage |

```
yarn run upgrade -dt              # deps + transitive only
yarn run upgrade --all --dry-run  # preview everything, change nothing
```

Notes:

- `react`, `react-dom`, and `react-router-dom` are auto-reconciled, as part of the `-d` phase, to the latest versions allowed by strapi's peer ranges — never beyond.
- Dependabot alerts (fetched via `gh` during the `-d` phase) trigger bumps to latest; if the `gh` fetch fails, this step is skipped with a warning — the rest of the run continues.
- The script never commits; inspect `git diff` before committing.

Development: `bash scripts/all.spec.bash` runs the script's test suite.

More from the Strapi default README:

# 🚀 Getting started with Strapi

Strapi comes with a full featured [Command Line Interface](https://docs.strapi.io/developer-docs/latest/developer-resources/cli/CLI.html) (CLI) which lets you scaffold and manage your project in seconds.

### `develop`

Start your Strapi application with autoReload enabled. [Learn more](https://docs.strapi.io/developer-docs/latest/developer-resources/cli/CLI.html#strapi-develop)

```
npm run develop
# or
yarn develop
```

### `start`

Start your Strapi application with autoReload disabled. [Learn more](https://docs.strapi.io/developer-docs/latest/developer-resources/cli/CLI.html#strapi-start)

```
npm run start
# or
yarn start
```

### `build`

Build your admin panel. [Learn more](https://docs.strapi.io/developer-docs/latest/developer-resources/cli/CLI.html#strapi-build)

```
npm run build
# or
yarn build
```

## ⚙️ Deployment

Strapi gives you many possible deployment options for your project. Find the one that suits you on the [deployment section of the documentation](https://docs.strapi.io/developer-docs/latest/setup-deployment-guides/deployment.html).

## 📚 Learn more

- [Resource center](https://strapi.io/resource-center) - Strapi resource center.
- [Strapi documentation](https://docs.strapi.io) - Official Strapi documentation.
- [Strapi tutorials](https://strapi.io/tutorials) - List of tutorials made by the core team and the community.
- [Strapi blog](https://docs.strapi.io) - Official Strapi blog containing articles made by the Strapi team and the community.
- [Changelog](https://strapi.io/changelog) - Find out about the Strapi product updates, new features and general improvements.

Feel free to check out the [Strapi GitHub repository](https://github.com/strapi/strapi). Your feedback and contributions are welcome!

## ✨ Community

- [Discord](https://discord.strapi.io) - Come chat with the Strapi community including the core team.
- [Forum](https://forum.strapi.io/) - Place to discuss, ask questions and find answers, show your Strapi project and get feedback or just talk with other Community members.
- [Awesome Strapi](https://github.com/strapi/awesome-strapi) - A curated list of awesome things related to Strapi.

---

<sub>🤫 Psst! [Strapi is hiring](https://strapi.io/careers).</sub>
