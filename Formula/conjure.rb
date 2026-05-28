class Conjure < Formula
  desc "Missing init kit for Claude Code — scaffolds a four-layer harness in one command"
  homepage "https://github.com/mohandoz/conjure"
  url "https://github.com/mohandoz/conjure/archive/refs/tags/v0.5.0.tar.gz"
  sha256 "2f246342f9706b346c35d60b35f8d159828f6e613d3d90eecb1fdbb8f29a19f5"
  license "MIT"

  def install
    (share/"conjure").install "cli", "scripts", "profiles", "compliance",
                              "migrations", "templates", "lib", "VERSION"

    (bin/"conjure").write <<~SH
      #!/bin/bash
      export CONJURE_HOME="#{share}/conjure"
      exec "#{share}/conjure/cli/conjure" "$@"
    SH
  end

  test do
    system bin/"conjure", "version"
  end
end
