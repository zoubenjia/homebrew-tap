class SitMonitor < Formula
  include Language::Python::Virtualenv

  desc "Posture monitor using MacBook camera with MediaPipe Pose detection"
  homepage "https://github.com/zoubenjia/sit-position"
  url "https://github.com/zoubenjia/sit-position.git", tag: "v1.5.0"
  license "MIT"

  depends_on "python@3.12"
  depends_on :macos

  # mediapipe 预编译 wheel 的 dylib header 空间不足，跳过 linkage 修复
  skip_clean "libexec"

  def install
    # 创建 Python 虚拟环境并安装包（含所有依赖）
    virtualenv_create(libexec, "python3.12")
    system libexec/"bin"/"python", "-m", "pip", "install", "--no-cache-dir", buildpath

    # 下载 ML 模型文件
    data_dir = libexec/"share"/"sit-monitor"
    data_dir.mkpath
    system "curl", "-sSL", "-o", data_dir/"pose_landmarker_lite.task",
           "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task"
    system "curl", "-sSL", "-o", data_dir/"face_landmarker.task",
           "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task"

    # 创建带环境变量的启动脚本
    (bin/"sit-monitor").write <<~SH
      #!/bin/bash
      export SITMONITOR_DATA_DIR="#{data_dir}"
      exec "#{libexec}/bin/sit-monitor" "$@"
    SH

    # 写入正确的 LaunchAgent plist（只限 Aqua session，确保菜单栏图标可见）
    plist_label = "homebrew.mxcl.sit-monitor"
    (prefix/"#{plist_label}.plist").write <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>Label</key>
        <string>#{plist_label}</string>
        <key>ProgramArguments</key>
        <array>
          <string>#{opt_bin}/sit-monitor</string>
          <string>--tray</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
        <key>KeepAlive</key>
        <true/>
        <key>LimitLoadToSessionType</key>
        <string>Aqua</string>
        <key>StandardOutPath</key>
        <string>#{var}/log/sit-monitor.log</string>
        <key>StandardErrorPath</key>
        <string>#{var}/log/sit-monitor-error.log</string>
      </dict>
      </plist>
    XML

    # 创建 LaunchAgent 管理脚本（brew services 生成的 plist 会有错误 session type）
    (bin/"sit-monitor-service").write <<~SH
      #!/bin/bash
      PLIST_SRC="#{opt_prefix}/homebrew.mxcl.sit-monitor.plist"
      PLIST_DST="$HOME/Library/LaunchAgents/homebrew.mxcl.sit-monitor.plist"
      LABEL="homebrew.mxcl.sit-monitor"

      case "${1:-}" in
        install)
          mkdir -p "$HOME/Library/LaunchAgents"
          cp "$PLIST_SRC" "$PLIST_DST"
          launchctl load -w "$PLIST_DST"
          echo "已安装并启动 SitMonitor 开机自启"
          ;;
        uninstall)
          launchctl unload "$PLIST_DST" 2>/dev/null || true
          rm -f "$PLIST_DST"
          echo "已卸载 SitMonitor 开机自启"
          ;;
        start)
          cp "$PLIST_SRC" "$PLIST_DST"
          launchctl load -w "$PLIST_DST"
          echo "已启动 SitMonitor"
          ;;
        stop)
          launchctl unload "$PLIST_DST" 2>/dev/null || true
          rm -f "$PLIST_DST"
          echo "已停止 SitMonitor"
          ;;
        *)
          echo "用法: sit-monitor-service {install|uninstall|start|stop}"
          echo "  install   安装开机自启（推荐替代 brew services start）"
          echo "  uninstall 卸载开机自启"
          echo "  start     启动"
          echo "  stop      停止"
          ;;
      esac
    SH
  end

  def caveats
    <<~EOS
      Usage:
        sit-monitor --tray           # Menu bar mode (recommended)
        sit-monitor --debug          # Debug mode (show camera window)
        sit-monitor                  # CLI mode

      First run:
        Camera access permission is required.
        Go to System Settings > Privacy & Security > Camera to grant access.

      Auto-start on login (menubar icon support):
        sit-monitor-service install

      Note: Use sit-monitor-service instead of brew services to ensure
      the menu bar icon displays correctly.
    EOS
  end

  test do
    assert_match "坐姿监控", shell_output("#{bin}/sit-monitor --help 2>&1", 0)
  end
end
