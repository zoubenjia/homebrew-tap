class SitMonitor < Formula
  desc "Posture monitor using MacBook camera with MediaPipe Pose detection"
  homepage "https://github.com/zoubenjia/sit-position"
  url "https://github.com/zoubenjia/sit-position.git", branch: "main"
  version "1.1.0"
  license "MIT"

  depends_on "python@3.12"
  depends_on "uv"
  depends_on :macos

  def install
    # 创建虚拟环境并安装依赖
    venv = libexec/"venv"
    system "uv", "venv", "--python", "python3.12", venv.to_s
    system "uv", "pip", "install", "--python", "#{venv}/bin/python",
           "-r", "requirements.txt"

    # 下载模型文件
    model_url = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task"
    system "curl", "-sSL", "-o", "pose_landmarker_lite.task", model_url

    # 安装项目文件
    libexec.install Dir["*"]

    # 创建启动脚本
    (bin/"sit-monitor").write <<~EOS
      #!/bin/bash
      exec "#{libexec}/venv/bin/python" "#{libexec}/sit_monitor.py" "$@"
    EOS

    # 创建服务管理脚本
    (bin/"sit-monitor-service").write <<~EOS
      #!/bin/bash
      exec bash "#{libexec}/service.sh" "$@"
    EOS
  end

  def caveats
    <<~EOS
      Usage:
        sit-monitor --tray           # System tray mode
        sit-monitor --debug          # Debug mode (show camera)
        sit-monitor --auto-pause     # CLI mode

      Service management:
        sit-monitor-service start    # Start background service
        sit-monitor-service install  # Install LaunchAgent (auto-start on login)
        sit-monitor-service stop     # Stop service

      Note: Camera access permission is required.
      Go to System Settings > Privacy & Security > Camera to grant access.
    EOS
  end

  test do
    system "#{bin}/sit-monitor", "--help"
  end
end
