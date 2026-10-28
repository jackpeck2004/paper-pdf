cask "paper-pdf" do
  version "0.2.1"
  sha256 "556519bf758055b1c9269dc47faa206cb1bff3a56688bc6b46b9178fd62e18c3"

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
