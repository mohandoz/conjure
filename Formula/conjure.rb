class Conjure < Formula
  desc "Missing init kit for Claude Code — scaffolds a four-layer harness in one command"
  homepage "https://github.com/mohandoz/conjure"
  url "https://github.com/mohandoz/conjure/archive/refs/tags/v0.3.0.tar.gz"
  sha256 "PLACEHOLDER_SHA256_REPLACE_ON_FIRST_RELEASE"
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
