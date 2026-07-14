cask "apollogene" do
  version "200b6"
  sha256 "2bf92aab9473246bed2d5cad52d19d6d13643c13ca06168bf32b5cf4f37e1702"

  url "https://github.com/dtseto/Hermes-master/releases/download/v#{version}/ApolloGene#{version}-n.zip"
  name "ApolloGene"
  desc "Pandora client for Intel and Apple Silicon Macs"
  homepage "https://github.com/dtseto/Hermes-master"

  depends_on macos: :big_sur

  app "ApolloGene#{version}-n.app", target: "ApolloGene.app"

  zap trash: [
    "~/Library/Preferences/com.davidseto.ApolloGene.plist",
    "~/Library/Saved Application State/com.davidseto.ApolloGene.savedState",
  ]
end
