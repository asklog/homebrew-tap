# The asklog Homebrew tap

This directory **is** the tap. Its contents are pushed to the public GitHub
repository `asklog/homebrew-tap`, which Homebrew calls `asklog/tap`:

    brew tap asklog/tap
    brew install asklog/tap/asklog          # the command line
    brew install --cask asklog/tap/asklog-app   # the Mac app

Homebrew derives the tap name from the repository name and drops a leading
`homebrew-`, so the repository has to be called exactly `homebrew-tap` for those
commands to work. `HOMEBREW_TAP` in `apps/web-cloud/lib/release.ts` is the one
place that name is decided, and the site prints commands built from it.

It lives here rather than only in that repository so that it is reviewed in the
release's own pull request, beside the version and checksum it installs, and so
`apps/web-cloud/test/packaging.test.ts` can fail when the two disagree. The tap
repository is a publishing target, not a source of truth.

## What is in it

| File | Installs | State |
|---|---|---|
| `Casks/asklog-app.rb` | the signed, notarized Mac app | live - tracks `MAC_APP_BUILD`, today 0.1.1 |
| `Formula/asklog.rb` | the `asklog` command | rendered at release time from `Formula/asklog.rb.in` |

`Formula/asklog.rb` is **absent until a release publishes a command-line
tarball**, and that is deliberate. A formula names a version, a URL and a
checksum; none of the three exists yet, because every release published so far
predates `apps/cli/scripts/build-cli.mjs` and each of their prefixes is
append-only, so none of them can ever gain one. A file carrying placeholders
would be a broken formula in the tap and a file carrying invented values would
be worse. `docs/desktop-release.md` runs

    node packaging/render-formula.mjs apps/cli/release/asklog-cli-VERSION.json

which substitutes exactly `@VERSION@` and `@SHA256@` and writes the real file.

## Formula for the command, cask for the app

A cask installs a `.app` bundle; a formula installs a command. That is the whole
of the split, and it is why the two names differ: `asklog` is the formula, so
`brew install asklog/tap/asklog` gives somebody the command the site prints for
the command line. A cask sharing that token would resolve to the formula anyway and
print a conflict warning on every install (Homebrew 6.0.13, `cli/named_args.rb`),
so the app is `asklog-app` - the same shape as Homebrew core's `docker` formula
beside its `docker-desktop` cask.

Neither ships the daemon. `docs/package-managers.md` argues that in full.

## Staying current

Both stanzas carry a `livecheck` block pointing at
`desktop/stable/latest-mac.yml`, the release channel pointer, so
`brew livecheck --tap asklog/tap` reports a newer release without anybody
editing anything. That is a *report*, not an update: the values in these files
still move in the release's own commit, which is what keeps the checksum a
reviewed fact.

The cask also sets `auto_updates true`, because the app updates itself through a
signed channel Squirrel.Mac verifies against the installed app's own designated
code-signing requirement. `brew upgrade` therefore leaves it alone unless
somebody asks with `--greedy`, which is correct: brew replacing the app
underneath its own updater would be a weaker chain, not a stronger one.

## Uninstalling

`brew uninstall asklog` removes a command and nothing else. The formula starts
nothing, registers nothing and writes nothing outside its keg.

`brew uninstall --cask asklog-app` removes the app **and stops the daemon**,
which ends the terminal sessions running on it. That is not tidiness: the app is
a window onto hubd and ptyd, which deliberately outlive it, so removing the app
and stopping there leaves two daemons on a machine that no longer has anything
that can manage or update them. The cask's `uninstall script:` reads the pid out
of `hubd.json` and `ptyd/ptyd-v*.pid` under `TL_HOME`, refuses anything that is
not a positive integer above 1 naming a live process, and sends one SIGTERM. It
never escalates and never matches a process by name.

`brew uninstall --zap --cask asklog-app` additionally removes `~/.tl-code` and
the app's data. `~/.tl-code` holds the identity key every signed-in device
pinned, so a zap cuts every phone and browser off this machine and cannot be
undone - which is exactly why it is opt-in and why a plain uninstall must never
do it.

Nothing asklog installs registers itself to start with the machine: no launch
agent and no login item, on purpose
(`apps/daemon/src/hubd/reach/connector.ts` records why the connector is a
supervised child process rather than a launchd agent). The one launchd entry
that does exist is Squirrel.Mac's `ai.asklog.app.ShipIt`, submitted by Electron
so it can replace the bundle on quit - a session-scoped submitted job with no
plist, so it starts nothing at boot and does not survive a logout.
`docs/package-managers.md` has it measured. So there is nothing of that kind
persisting for an uninstall to miss.
