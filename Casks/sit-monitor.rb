cask "sit-monitor" do
  version "1.5.8"
  sha256 "dcbaf4d861882fb75930c95096b9e12aca576d744c4fa230542bc4d078d4bb15"

  url "https://github.com/zoubenjia/sit-position/releases/download/v#{version}/SitMonitor-macOS.dmg"
  name "Sit Monitor"
  desc "Posture monitor using MacBook camera with MediaPipe Pose detection"
  homepage "https://github.com/zoubenjia/sit-position"

  # 从 Formula 迁来的原因（2026-10-22）：
  # formula 用 Homebrew venv 跑，进程身份是 Cellar 里的 python3.12，TCC 按完整
  # 路径记授权 → 每次 brew 升级 python@3.12 都换路径 → 摄像头/自动化授权失效，
  # 反复弹窗（已重复 8 次）。改为装 Developer ID 签名的 .app：TCC 按 bundle 的
  # designated requirement 记授权，稳定不变。
  #
  # 另一个消失的坑：formula 时代 brew 对 wheel 里的 dylib 做 relocation 破坏签名，
  # 被 AMFI 拒载导致闪退，需要 post_install 重签约 97 个库。Cask 装预构建包，
  # brew 完全不碰二进制，该故障模式不存在。
  depends_on macos: :big_sur

  app "SitMonitor.app"
  binary "#{appdir}/SitMonitor.app/Contents/MacOS/SitMonitor", target: "sit-monitor"

  uninstall launchctl: "com.zoubenjia.sitmonitor",
            quit:      "com.zoubenjia.sitmonitor"

  # 刻意不 zap 数据目录的 history：2026-09-08 曾因数据放在 Cellar 被 cleanup
  # 删除而丢过历史，靠 APFS 快照救回。只清缓存与日志，history 留给用户自己决定。
  zap trash: [
    "~/Library/LaunchAgents/com.zoubenjia.sitmonitor.plist",
    "~/Library/Logs/SitMonitor",
  ]

  caveats <<~EOS
    安装必须带 --no-quarantine：

      brew install --cask --no-quarantine zoubenjia/tap/sit-monitor

    本包用 Developer ID 签名但**未公证**（Apple 开发者协议过期，notarytool 返回
    403）。不加该参数，Gatekeeper 会拒绝启动从网络下载的未公证包。

    首次运行需授权摄像头：系统设置 > 隐私与安全性 > 摄像头。
    开机自启在托盘菜单里开启（进阶模式 > 开机自启）。
  EOS
end
