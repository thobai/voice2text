class Voice2text < Formula
  desc "Push-to-talk voice transcription for macOS with local AI processing"
  homepage "https://github.com/thobai/voice2text"
  url "https://github.com/thobai/voice2text.git", tag: "v0.1.0", revision: "f195ca7"
  license "MIT"
  head "https://github.com/thobai/voice2text.git", branch: "main"

  depends_on :macos
  depends_on :xcode => ["15.0", :build]
  depends_on "cmake" => :build

  resource "whisper.cpp" do
    url "https://github.com/ggml-org/whisper.cpp.git", branch: "master"
  end

  def install
    # Build whisper.cpp xcframework
    resource("whisper.cpp").stage do
      system "bash", "build-xcframework.sh"
      (buildpath/"whisper.xcframework").install Dir["build-apple/whisper.xcframework/*"]
    end

    # Build Voice2Text
    system "swift", "build", "-c", "release"

    # Create .app bundle
    app_dir = prefix/"Voice2Text.app/Contents"
    (app_dir/"MacOS").mkpath
    (app_dir/"Frameworks").mkpath

    cp ".build/release/Voice2Text", app_dir/"MacOS/Voice2Text"
    cp "Resources/Info.plist", app_dir/"Info.plist"

    # Copy whisper framework into bundle
    cp_r "whisper.xcframework/macos-arm64_x86_64/whisper.framework", app_dir/"Frameworks/"

    # Add rpath and sign
    system "install_name_tool", "-add_rpath", "@executable_path/../Frameworks",
           app_dir/"MacOS/Voice2Text"
    system "codesign", "-s", "-", "--force", "--deep", prefix/"Voice2Text.app"
  end

  def caveats
    <<~EOS
      Voice2Text requires Accessibility permission for the global hotkey.
      Grant it in: System Settings > Privacy & Security > Accessibility

      To start Voice2Text:
        open #{prefix}/Voice2Text.app

      Or run directly (inherits terminal accessibility):
        #{prefix}/Voice2Text.app/Contents/MacOS/Voice2Text &

      On first run, whisper and LLM models will be downloaded (~1.5GB).

      Usage: Hold Right Command to record, release to transcribe and paste.
    EOS
  end

  service do
    run [opt_prefix/"Voice2Text.app/Contents/MacOS/Voice2Text"]
    keep_alive true
    log_path var/"log/voice2text.log"
    error_log_path var/"log/voice2text.log"
  end

  test do
    assert_predicate prefix/"Voice2Text.app/Contents/MacOS/Voice2Text", :exist?
  end
end
