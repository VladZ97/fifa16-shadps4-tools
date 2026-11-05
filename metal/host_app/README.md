FIFA 16 GPU.app: the Metal GPU host (bbgpu-host, bbgpu-host-macos27 copied from bloodborne_mac_port/out)
wrapped in an app bundle so macOS treats it as a game (Game Mode, LSApplicationCategoryType) and
lets it use the display's safe-area compatibility mode (NSPrefersDisplaySafeAreaCompatibilityMode:
full-screen below the notch, direct presentation). Use with BB_GPU_HOST="<this app>/Contents/MacOS/bbgpu-host".
Refresh the copies after rebuilding the host: bash ~/fifa_metal/host_app/refresh.sh
