cask "c5h" do
  version "0.2.0"
  sha256 :no_check # Update with actual SHA256 for release

  url "https://github.com/zaai/c5h/releases/download/v#{version}/C5h_#{version}_aarch64.dmg",
      verified: "github.com/zaai/c5h/"

  # For Intel Macs
  on_intel do
    url "https://github.com/zaai/c5h/releases/download/v#{version}/C5h_#{version}_x86_64.dmg",
        verified: "github.com/zaai/c5h/"
  end

  name "C5h"
  desc "AI Tool Usage Tracker - Visualize and optimize your Claude Code, Codex, and Gemini usage windows"
  homepage "https://github.com/zaai/c5h"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :ventura"

  app "C5h.app"

  zap trash: [
    "~/Library/Application Support/com.zaai.c5h",
    "~/Library/Caches/com.zaai.c5h",
    "~/Library/LaunchAgents/com.zaai.c5h.trigger.*.plist",
    "~/Library/Preferences/com.zaai.c5h.plist",
    "~/Library/Saved Application State/com.zaai.c5h.savedState",
  ]
end
