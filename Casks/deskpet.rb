cask "deskpet" do
  version "1.1"
  sha256 "b35faef9006abe1ace6bd819ba804b0fe06b5e7960cc1e77e65a4c6bd0055ac6"

  url "https://github.com/BansalAakash/DeskPet/releases/download/v#{version}/DeskPet-v#{version}-macOS-app.zip",
      verified: "github.com/BansalAakash/DeskPet/"
  name "DeskPet"
  desc "Menu-bar desktop pet that peeks in from the edge of the screen"
  homepage "https://github.com/BansalAakash/DeskPet"

  depends_on macos: ">= :ventura"

  app "DeskPet.app"

  uninstall quit: "com.aakash.deskpet"

  zap trash: [
    "~/Library/Preferences/com.aakash.deskpet.plist",
  ]

  caveats <<~EOS
    DeskPet is signed ad-hoc rather than notarised by Apple, so Homebrew's
    quarantine flag will make macOS refuse the first launch. Either install
    with:

      brew install --cask --no-quarantine deskpet

    or approve it once in System Settings > Privacy & Security.

    To avoid the question entirely, build it yourself — see the README.
  EOS
end
