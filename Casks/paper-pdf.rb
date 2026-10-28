cask "paper-pdf" do
  version "0.2.3"
  sha256 "8d76c4bca37f11a151091cac369be8c45f9dad8e4ebf40abef43fd650f53c4f3"

  url "https://github.com/jackpeck2004/paper-pdf/releases/download/v#{version}/Paper-#{version}-universal.zip",
      verified: "github.com/jackpeck2004/paper-pdf/"
  name "Paper"
  desc "Native PDF editor with annotations, text correction, and OCR"
  homepage "https://github.com/jackpeck2004/paper-pdf"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Paper.app"

  caveats <<~EOS
    This development build is ad-hoc signed and is not notarized by Apple.
    macOS may require your approval in System Settings > Privacy & Security
    before its first launch. This cask does not disable Gatekeeper or quarantine.
  EOS
end
