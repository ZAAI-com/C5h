# Homebrew cask template for C5h.
#
# This is a TEMPLATE — replace VERSION_PLACEHOLDER and SHA256_PLACEHOLDER before
# copying into the tap repo at github.com/ZAAI-com/homebrew-tap.
# .github/workflows/release-tap.yml does this automatically on release publish.
#
# Install: brew install --cask zaai-com/tap/c5h
# See Docs/RELEASING.md for the full release procedure.
cask "c5h" do
  version "VERSION_PLACEHOLDER"
  sha256 "SHA256_PLACEHOLDER"

  url "https://github.com/ZAAI-com/C5h/releases/download/v#{version}/C5h_#{version}_universal.dmg",
      verified: "github.com/ZAAI-com/C5h/"

  name "C5h"
  desc "AI coding-tool usage window tracker for Claude Code, Codex, and Gemini"
  homepage "https://github.com/ZAAI-com/C5h"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :monterey"

  app "C5h.app"

  zap trash: [
    "~/Library/Application Support/com.zaai.c5h",
    "~/Library/Caches/com.zaai.c5h",
    "~/Library/LaunchAgents/com.zaai.c5h.trigger.*.plist",
    "~/Library/Logs/com.zaai.c5h",
    "~/Library/Preferences/com.zaai.c5h.plist",
    "~/Library/Saved Application State/com.zaai.c5h.savedState",
  ]
end
