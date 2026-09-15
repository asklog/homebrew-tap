# The asklog Mac app, as a Homebrew cask.
#
# This is a convenience, not a gap: the app already has a signed, notarized
# download at a stable immutable URL with a published checksum, and it updates
# itself. What the cask adds is one line in a declarative machine config -
# `homebrew.casks = [ "asklog-app" ]` under nix-darwin - and an uninstall that
# leaves nothing running.
#
# Cask and not formula, because it installs a `.app` bundle from a DMG. A
# formula would have to unpack an application into `libexec` and symlink it,
# which breaks Gatekeeper's expectations about where a notarized app lives.
#
# `asklog-app` and not `asklog`, because `asklog` is the formula that installs
# the command line, which is the name the site prints for it. A cask and
# a formula sharing one token in a third-party tap resolve to the formula with a
# conflict warning printed on every install (Homebrew 6.0.13,
# `cli/named_args.rb`), and a warning on every install is not a thing to ship.
# Homebrew core does the same thing with `docker` beside `docker-desktop`.
#
# Everything version-shaped here is copied from `apps/web-cloud/lib/release.ts`,
# which is the one place a published build is recorded, and
# `apps/web-cloud/test/packaging.test.ts` fails if the two ever disagree.
cask "asklog-app" do
  version "1.3.0"
  sha256 "51da217ebe830afc61fb09397e9c543894ab5cac6323a124082876b9007d7246"

  url "https://releases.asklog.ai/desktop/releases/#{version}/asklog-#{version}-mac-universal.dmg",
      verified: "releases.asklog.ai/desktop/releases/"
  name "asklog"
  desc "Attach to live terminal sessions on your own machines"
  homepage "https://asklog.ai/"

  # The one mutable channel pointer the app's own updater reads. It is named
  # for macOS because the updater is the Mac app's, but it is the release
  # channel: the command line is cut from the same release under the same
  # version, so `Formula/asklog.rb` watches this same object.
  livecheck do
    url "https://releases.asklog.ai/desktop/stable/latest-mac.yml"
    strategy :electron_builder
  end

  # The app downloads and stages its own signed updates and applies them when
  # somebody restarts it. That chain is stronger than this one - Squirrel.Mac
  # enforces the installed app's designated code-signing requirement - so brew
  # must not race it. `brew upgrade` therefore leaves this alone unless somebody
  # asks with `--greedy`.
  auto_updates true
  # This describes **the published bundle**, never the build configuration,
  # and `MAC_APP_BUILD` is the only place that distinction is recorded. Every
  # release since 0.1.2 is universal, so there is no `depends_on arch:` line at
  # all - one that kept `:arm64` would refuse every Intel Mac the artifact was
  # made universal for - and the floor is what the published bundle's
  # `Info.plist` declares, `LSMinimumSystemVersion 11.0`, read back off the
  # 1.1.0 DMG on 2026-09-14.
  #
  # Big Sur is macOS 11, which is `MAC_APP_BUILD.minimumOs`. The bare symbol
  # *is* the minimum: `">= :big_sur"` is the deprecated spelling of this exact
  # requirement and Homebrew 6.0.13 warns on it at load time.
  # `apps/web-cloud/test/packaging.test.ts` fails if this drifts from the
  # record.
  depends_on macos: :big_sur

  app "asklog.app"

  # Uninstalling has to stop the daemon, and the daemon is not the app.
  #
  # The app is a window onto hubd and ptyd, which are separate processes that
  # deliberately outlive it - closing the app keeps sessions running, which is
  # the whole point of the product. So removing the app and stopping there
  # leaves two daemons on a machine that no longer has anything that can manage
  # or update them.
  #
  # Both write a pid where something else can read it: `hubd.json` and
  # `ptyd/ptyd-v*.pid` under `TL_HOME` (default `~/.tl-code`). This reads those,
  # refuses anything that is not a positive integer naming a live process, and
  # sends one SIGTERM. It never escalates to SIGKILL and never matches on a
  # process name: a pid in a file is not authority to signal, `pkill` against a
  # script path matches every checkout on the machine, and this runs while
  # somebody may be using another one.
  #
  # `must_succeed: false` because failing to stop a daemon must not leave a
  # half-uninstalled app behind.
  uninstall quit:   "ai.asklog.app",
            script: {
              executable:   "/bin/bash",
              args:         ["-c", <<~BASH],
                set -u
                home="${TL_HOME:-$HOME/.tl-code}"
                stop() {
                  [ -f "$1" ] || return 0
                  pid="$(/usr/bin/plutil -extract pid raw -o - "$1" 2>/dev/null)" || return 0
                  case "$pid" in ''|*[!0-9]*) return 0 ;; esac
                  [ "$pid" -gt 1 ] || return 0
                  kill -0 "$pid" 2>/dev/null || return 0
                  echo "asklog: stopping daemon pid $pid"
                  kill -TERM "$pid" 2>/dev/null || true
                }
                stop "$home/hubd.json"
                for lock in "$home"/ptyd/ptyd-v*.pid; do stop "$lock"; done
                exit 0
              BASH
              must_succeed: false,
            }

  # `zap` is opt-in (`brew uninstall --zap`) and that is right here: `~/.tl-code`
  # holds the identity key every signed-in device pinned, the account claim, and
  # every session's scrollback. Removing it cuts off every phone and browser
  # that had this machine, and cannot be undone, so it must never happen on a
  # plain uninstall.
  #
  # The `@tl-code` paths are measured, not guessed: Electron derives userData
  # from `apps/desktop/package.json`'s `name`, which is still the package
  # namespace rather than the product name (AD-008 covers user-visible strings;
  # this directory escaped it). Renaming it is a data migration for the
  # installed base, so this matches what is on disk rather than what it should
  # be called - see `docs/package-managers.md`.
  #
  # `~/Library/Application Support/asklog` is the machine's *identity* anchor -
  # a copy of the host key kept outside `~/.tl-code` so that replacing that
  # directory no longer adds a second entry to the owner's account
  # (`apps/daemon/src/hubd/security/machine-anchor.ts`). It is in `zap` and not
  # in the plain uninstall for the same reason `~/.tl-code` is, and it belongs
  # in `zap` rather than being spared: `zap` means "leave nothing", and after
  # one this Mac genuinely is a new machine to every device that pinned it. The
  # consequence to expect, and it is correct rather than a regression: a zap and
  # reinstall leaves the old entry in the account, which is what the Remove
  # control on the account's machine list is for.
  zap trash: [
        "~/.tl-code",
        "~/Library/Application Support/asklog",
        "~/Library/Application Support/@tl-code/desktop",
        "~/Library/Caches/@tl-codedesktop-updater",
        "~/Library/Caches/ai.asklog.app",
        "~/Library/Caches/ai.asklog.app.ShipIt",
        "~/Library/Logs/asklog",
        "~/Library/Preferences/ai.asklog.app.plist",
        "~/Library/Saved Application State/ai.asklog.app.savedState",
      ],
      rmdir: "~/Library/Application Support/@tl-code"

  caveats <<~EOS
    asklog is a window onto a daemon that owns your terminal sessions. The app
    carries that daemon and starts it; nothing else on this machine does.

    Uninstalling stops the daemon, which ends every session running on it.
    `brew uninstall --zap --cask #{token}` also removes ~/.tl-code, which
    discards this machine's identity. Your other devices lose access to it,
    and it cannot be undone. Your account will still list this machine;
    remove it under Your machines.
  EOS
end
