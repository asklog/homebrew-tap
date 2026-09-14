# The asklog command line, 1.1.0.
#
# Generated from Formula/asklog.rb.in by packaging/render-formula.mjs. Edit
# the template, not this file, and re-render at the next release.
class Asklog < Formula
  desc "Attach to live terminal sessions on your own machines"
  homepage "https://asklog.ai/"
  # No `version` line: Homebrew scans it out of `asklog-cli-VERSION.tar.gz` and
  # `brew audit` refuses the explicit one as redundant (measured against
  # Homebrew 6.0.13). The filename is therefore load-bearing - a release that
  # renamed the tarball would silently change what the formula calls itself.
  url "https://releases.asklog.ai/desktop/releases/1.1.0/asklog-cli-1.1.0.tar.gz"
  sha256 "5a683a759b4dc2df7408b9dde5818d4fd7b25716131f8f79120d65e664e4882e"

  # Formula and not cask: this is a command, and casks are for `.app` bundles.
  # It is also the half of asklog that has never had an installer of any kind,
  # which is why it is the one worth packaging - the app already had a signed
  # download with a checksum before this tap existed.
  #
  # The tarball is one esbuild bundle plus a launcher. The command has no native
  # dependency at all - `ws` and `qrcode-terminal` are plain JavaScript - so one
  # artifact runs on every platform Node runs on and there is nothing here to
  # compile or to build per architecture.

  # The release channel pointer. It is named for macOS because the app's updater
  # owns it, but a release publishes the app and the command under one version
  # into one prefix, so this is the object that answers "is there a newer
  # asklog". `apps/cli/scripts/build-cli.mjs` reads the same version out of
  # `apps/desktop/package.json`, which is what keeps that true.
  livecheck do
    url "https://releases.asklog.ai/desktop/stable/latest-mac.yml"
    strategy :electron_builder
  end

  depends_on "node"

  def install
    libexec.install "bin", "package.json", "README.md"
    # A wrapper rather than a symlink, so the command runs against Homebrew's
    # own Node rather than whatever `#!/usr/bin/env node` finds first. A version
    # manager on the PATH is the common case on a developer machine and the
    # bundle targets Node 22.
    #
    # Belt and braces, deliberately: Homebrew's own cleaner already rewrites
    # `#!/usr/bin/env node` to this exact interpreter on the way into the Cellar
    # (`Cleaner#rewrite_shebangs`, measured on 6.0.13 - the installed bundle
    # came out carrying an absolute `opt/node/bin/node` shebang). This wrapper
    # is what keeps that a convenience rather than the only thing standing
    # between the bundle and somebody's Node 20.
    node_path = "#{formula_opt_bin("node")}:$PATH"
    (bin/"asklog").write_env_script libexec/"bin/asklog.mjs", PATH: node_path
    # The deprecation alias, for as long as any shipped build still prints `tl`
    # at somebody. Its own header argues why it exists; the reason it is here is
    # that a build printing `tl pair` reaching somebody who installed through
    # this tap would otherwise be `command not found`.
    (bin/"tl").write_env_script libexec/"bin/tl.mjs", PATH: node_path
  end

  def caveats
    <<~EOS
      This installs the asklog command only. It does not install the daemon that
      owns your terminal sessions - that ships inside the asklog app, and
      nothing else on this machine starts it.

      https://asklog.ai/install says what is published where.
    EOS
  end

  test do
    assert_match "asklog - attach to live terminal sessions",
                 shell_output("#{bin}/asklog --help")

    # Port 9 is discard: nothing answers, and no daemon a person is using can be
    # reached by accident. What is being tested is that the bundled WebSocket
    # client and the product's own sentence for an absent daemon both survived
    # bundling, which `--help` alone does not reach.
    #
    # The expected status is 1 and is asserted rather than ignored - measured,
    # not assumed: an unreachable daemon is a failure and the CLI says so with
    # its exit code, which `apps/cli/test/exit-code.test.ts` measures on the
    # real process for the same reason this does.
    assert_match "Cannot reach the asklog daemon",
                 shell_output("#{bin}/asklog ls --port 9 2>&1", 1)
  end
end
