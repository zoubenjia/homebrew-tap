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

      Auto-start on login:
        brew services start sit-monitor
    EOS
  end

  service do
    run [opt_bin/"sit-monitor", "--tray"]
    keep_alive true
    log_path var/"log/sit-monitor.log"
    error_log_path var/"log/sit-monitor-error.log"
  end

  test do
    assert_match "坐姿监控", shell_output("#{bin}/sit-monitor --help 2>&1", 0)
  end
end
