cask "deskpet" do
  version "1.1"
  sha256 "714ff3794b94a41b58afb7849c7e33718f1af56b69697b03529270eb664de5e8"

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
    DeskPet is signed ad-hoc rather than notarised by Apple, so macOS will
    refuse the first launch. Approve it once:

      System Settings > Privacy & Security > scroll down > Open Anyway

    Every launch after that is normal. To skip the question entirely, build
    it from source instead — see the README.
  EOS
end
