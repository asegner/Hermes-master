cask "apollogene" do
  version "201b1"
  sha256 "233218cb60088a6011d6558a94bed335dcdeba85df769696c23c51d288817c2d"

  url "https://github.com/dtseto/Hermes-master/releases/download/v#{version}/ApolloGene-n.app.zip"
  name "ApolloGene"
  desc "Pandora client for Intel and Apple Silicon Macs"
  homepage "https://github.com/dtseto/Hermes-master"

  depends_on macos: :big_sur

  app "ApolloGene-n.app", target: "ApolloGene.app"

  zap trash: [
    "~/Library/Preferences/com.davidseto.ApolloGene.plist",
    "~/Library/Preferences/com.dtseto.ApolloGene.plist",
    "~/Library/Saved Application State/com.davidseto.ApolloGene.savedState",
    "~/Library/Saved Application State/com.dtseto.ApolloGene.savedState",
  ]
end
