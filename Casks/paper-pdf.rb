cask "paper-pdf" do
  version "0.2.0"
  sha256 "9c3cc99596551215339bc1d0392e3234347ab92a41a1137b572b5ea499a91497"

  url "https://github.com/jackpeck2004/paper-pdf/releases/download/v#{version}/Paper-#{version}-universal.zip",
      verified: "github.com/jackpeck2004/paper-pdf/"
  name "Paper"
  desc "Native PDF editor with annotations, text correction, and OCR"
  homepage "https://github.com/jackpeck2004/paper-pdf"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "Paper.app"

  caveats <<~EOS
    This development build is ad-hoc signed and is not notarized by Apple.
    macOS may require your approval in System Settings > Privacy & Security
    before its first launch. This cask does not disable Gatekeeper or quarantine.
  EOS
end
