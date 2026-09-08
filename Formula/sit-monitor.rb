class SitMonitor < Formula
  include Language::Python::Virtualenv

  desc "Posture monitor using MacBook camera with MediaPipe Pose detection"
  homepage "https://github.com/zoubenjia/sit-position"
  url "https://github.com/zoubenjia/sit-position.git", tag: "v1.5.8"
  license "MIT"

  depends_on "python@3.12"
  depends_on :macos

  # mediapipe 预编译 wheel 的 dylib header 空间不足，跳过 linkage 修复
  skip_clean "libexec"

  # Homebrew 安装后会对 wheel 里的 .dylib 做 relocation（改 install_name/rpath），
  # 这会破坏它们原有的 adhoc 代码签名 → macOS AMFI 拒绝加载 →
  #   amfid: "not valid ... adhoc signed or signed by an unknown certificate chain"
  # 进程一 import 就被 SIGKILL，表现为菜单栏程序反复闪退（launchctl status=-9）。
  #
  # 实测确认（2026-09-08）：主 cv2.abi3.so 未被改动，但 cv2/.dylibs/ 下约 97 个
  # 依赖库全部被改写；只重签主 .so 无效，必须重签全部。
  # post_install 跑在 brew 的后处理之后，是唯一不会被再次覆盖的时机
  # （写在 install 里会被后处理推翻，已验证无效）。
  def post_install
    Dir.glob(libexec/"lib/python3.12/site-packages/**/*.{dylib,so}").each do |f|
      system "/usr/bin/codesign", "--force", "--sign", "-", f
    end
  end

  def install
    # 创建 Python 虚拟环境并安装包（含所有依赖）
    virtualenv_create(libexec, "python3.12")
    system libexec/"bin"/"python", "-m", "pip", "install", "--no-cache-dir", buildpath

    # 强制把 certifi 装进 venv：mediapipe>=0.10.35 运行时调 certifi.where()，
    # 而部分机器全局 site-packages 的 certifi 是损坏的空目录（只剩 dist-info），
    # 普通 pip 会误判“已安装”而不装到 venv，导致姿势检测线程启动即崩。
    system libexec/"bin"/"python", "-m", "pip", "install",
           "--ignore-installed", "--no-cache-dir", "certifi"



    # 下载 ML 模型文件
    data_dir = libexec/"share"/"sit-monitor"
    data_dir.mkpath
    system "curl", "-sSL", "-o", data_dir/"pose_landmarker_lite.task",
           "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task"
    system "curl", "-sSL", "-o", data_dir/"face_landmarker.task",
           "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task"

    # 把模型复制到用户标准数据目录（wrapper 会把 SITMONITOR_DATA_DIR 指到那里）
    (bin/"sit-monitor-setup-data").write <<~SH
      #!/bin/bash
      D="${SITMONITOR_DATA_DIR:-$HOME/Library/Application Support/SitMonitor}"
      mkdir -p "$D"
      for f in pose_landmarker_lite.task face_landmarker.task; do
        [ -f "$D/$f" ] || cp "#{data_dir}/$f" "$D/$f"
      done
    SH
    chmod 0755, bin/"sit-monitor-setup-data"

    # 创建带环境变量的启动脚本
    (bin/"sit-monitor").write <<~SH
      #!/bin/bash
      # 数据目录默认放用户标准位置，不放 Cellar：
      # Cellar 里的数据会被 brew cleanup 在升级/重装时连同历史一起删掉
      # （2026-09-08 实际丢过一次，靠 APFS 本地快照才救回）。
      # 模型文件也在此目录下，安装时会一并复制过去。
      export SITMONITOR_DATA_DIR="${SITMONITOR_DATA_DIR:-$HOME/Library/Application Support/SitMonitor}"
      "#{bin}/sit-monitor-setup-data"
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
