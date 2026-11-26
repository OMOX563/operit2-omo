#!/usr/bin/env python3
import argparse
import os
import shutil
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
from build_windows_msi import build_windows_msi

from common import (
    DIST_DIR,
    release_asset_name,
    FLUTTER_APP_DIR,
    RELEASE_DIR,
    flutter_command,
    flutter_pub_get,
    prepare_plugin_assets,
    require_command,
    run,
)


# 把本地推理 DLL 补进给定的发布目录，供 MSI 打包收录。
# Fork 补丁：`package_windows_app` 走的是 `cmake --install` 到一个全新临时目录，而不是
# `build/windows/x64/runner/Release`；而 CMake 的 install 阶段可能早于桥接自定义构建产出
# `operit_local_llm.dll`（VS 生成器下真实落点是 `<bridge>/target/<profile>/build/`），
# 于是 MSI 里长期缺这个文件。这里在 install 之后、打 MSI 之前递归找一遍并复制进去；
# 找不到只告警（本地 LLM 不可用，其余功能不受影响）。
def deploy_local_llm_dll(destination_dir: Path) -> None:
    destination = destination_dir / "operit_local_llm.dll"
    if destination.is_file():
        return
    repo_root = FLUTTER_APP_DIR.parents[2]                       # <repo>
    bridge_target = FLUTTER_APP_DIR.parent / "native/operit-flutter-bridge/target"
    for root in (bridge_target, repo_root / "target/local-llm",
                 FLUTTER_APP_DIR / "build/windows/x64/runner/Release"):
        if not root.is_dir():
            continue
        for candidate in sorted(root.rglob("operit_local_llm.dll")):
            if candidate.is_file() and candidate.stat().st_size > 0:
                destination_dir.mkdir(parents=True, exist_ok=True)
                shutil.copy2(candidate, destination)
                print(f"Deployed local LLM engine: {candidate} -> {destination}", flush=True)
                return
    print("warning: operit_local_llm.dll not found; local LLM will be unavailable in this build",
          flush=True)


# Installs only the current CMake payload into a fresh tree before packaging it.
def package_windows_app(installer_path: Path) -> None:
    work = (RELEASE_DIR / "work").resolve()
    work.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(dir=work, prefix="windows-app-") as temporary:
        release_dir = Path(temporary).resolve()
        if release_dir.parent != work:
            raise RuntimeError(f"Windows release staging escapes its workspace: {work}")
        run([
            require_command("cmake"), "--install",
            FLUTTER_APP_DIR / "build/windows/x64", "--config", "Release",
            "--prefix", release_dir, "--component", "Runtime",
        ])
        deploy_local_llm_dll(release_dir)
        build_windows_msi(release_dir, installer_path)


# Parses command-line options for the Windows Flutter build.
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build the Operit2 Windows Flutter app.")
    parser.add_argument("--build-name")
    parser.add_argument("--build-number")
    parser.add_argument("--installer-path", type=Path)
    parser.add_argument("--enforce-lockfile", action="store_true")
    return parser.parse_args()


# Builds the Windows Flutter app and writes its MSI installer.
def main() -> int:
    args = parse_args()
    prepare_plugin_assets()
    flutter_pub_get(enforce_lockfile=args.enforce_lockfile)
    command = [flutter_command(), "build", "windows", "--release", "--no-pub"]
    # Fork 补丁：MSBuild 只回传 "CUSTOMBUILD : warning :" 行，真正的 cargo/CMake 错误会被吞掉，
    # 设 OPERIT_FLUTTER_VERBOSE=1 打开 flutter -v 以拿到完整子进程输出。
    if os.environ.get("OPERIT_FLUTTER_VERBOSE"):
        command.append("-v")
    if args.build_name:
        command.extend(["--build-name", args.build_name])
    if args.build_number:
        command.extend(["--build-number", args.build_number])
    run(command, cwd=FLUTTER_APP_DIR)
    installer_path = args.installer_path or DIST_DIR / release_asset_name("app", "windows", "x86_64", "msi")
    package_windows_app(installer_path)
    print(f"Windows installer: {installer_path}", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
