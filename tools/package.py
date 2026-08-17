#!/usr/bin/env python3
"""《晚自习之后》发布打包工具

把工程打成可直接导入 Godot 的完整项目 zip，输出到 dist/。

特性：
  * 强制 UTF-8 文件名标志位（0x800），避免 Windows 自带解压出现中文乱码
  * 顶层目录用 ASCII 名，兼容各类解压工具
  * 自动剔除 .godot / __pycache__ / dist 等构建产物
  * 打包前自动跑校验；打包后解压回验，确保产物可用

用法：
    python3 tools/package.py
    python3 tools/package.py --skip-checks     # 跳过校验（不推荐）
"""
import argparse
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VERSION = "1.0.0"
TOP = f"AfterEveningStudy_v{VERSION}"
OUT_CN = f"晚自习之后_完整项目_v{VERSION}.zip"
OUT_ASCII = f"AfterEveningStudy_v{VERSION}_full_project.zip"

INCLUDE = ["game", "tools", "README.md", "快速开始.txt", ".gitignore",
           "a.md", "b.md", "c.md", "d.md", "e.md", "f.md"]
EXCLUDE_DIRS = {".godot", ".import", "__pycache__", "dist", ".git", "node_modules"}
EXCLUDE_EXT = {".pyc", ".pyo", ".apk", ".aab", ".pck", ".exe", ".tmp"}


def run_checks():
    ok = True
    for script in ["validate_story.py", "check_gdscript.py"]:
        p = subprocess.run([sys.executable, os.path.join(ROOT, "tools", script)],
                           capture_output=True, text=True, cwd=ROOT)
        tail = [l for l in p.stdout.strip().split("\n") if "错误" in l]
        print(f"  {script:22s} {tail[-1] if tail else '（无输出）'}")
        if p.returncode != 0:
            ok = False
    p = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "simulate.py"),
                        "--runs", "300"], capture_output=True, text=True, cwd=ROOT)
    tail = [l for l in p.stdout.strip().split("\n") if l.startswith("结果:")]
    print(f"  {'simulate.py':22s} {tail[-1] if tail else '（无输出）'}")
    if p.returncode != 0:
        ok = False
    return ok


def collect():
    files = []
    for item in INCLUDE:
        src = os.path.join(ROOT, item)
        if not os.path.exists(src):
            print(f"  [warn ] 缺少 {item}，已跳过")
            continue
        if os.path.isfile(src):
            files.append((src, item))
            continue
        for base, dirs, fs in os.walk(src):
            dirs[:] = sorted(d for d in dirs if d not in EXCLUDE_DIRS)
            for f in sorted(fs):
                if os.path.splitext(f)[1] in EXCLUDE_EXT:
                    continue
                full = os.path.join(base, f)
                files.append((full, os.path.relpath(full, ROOT)))
    return files


def build(files, out_path):
    with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for full, rel in files:
            arc = f"{TOP}/{rel.replace(os.sep, '/')}"
            zi = zipfile.ZipInfo.from_file(full, arc)
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.flag_bits |= 0x800          # UTF-8 文件名，防止中文乱码
            with open(full, "rb") as fh, z.open(zi, "w") as zf:
                zf.write(fh.read())


def verify(out_path):
    """解压回验：确认产物完整、含工程入口、校验脚本能在解压副本上跑通"""
    with zipfile.ZipFile(out_path) as z:
        if z.testzip():
            return False, "压缩包损坏"
        names = z.namelist()
        if not any(n.endswith("game/project.godot") for n in names):
            return False, "缺少 game/project.godot"
        with tempfile.TemporaryDirectory() as td:
            z.extractall(td)
            root = os.path.join(td, TOP)
            p = subprocess.run([sys.executable, "tools/validate_story.py"],
                               capture_output=True, text=True, cwd=root)
            if p.returncode != 0:
                return False, "解压副本剧本校验失败"
    return True, f"{len(names)} 个文件"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skip-checks", action="store_true")
    args = ap.parse_args()

    print("=" * 62)
    print(f"《晚自习之后》发布打包  v{VERSION}")
    print("=" * 62)

    if not args.skip_checks:
        print("[1/4] 打包前校验")
        if not run_checks():
            print("\n校验未通过，已中止打包。")
            return 1
    else:
        print("[1/4] 已跳过校验")

    print("[2/4] 收集文件")
    files = collect()
    print(f"  共 {len(files)} 个文件")

    print("[3/4] 生成压缩包")
    dist = os.path.join(ROOT, "dist")
    os.makedirs(dist, exist_ok=True)
    out = os.path.join(dist, OUT_CN)
    build(files, out)
    shutil.copyfile(out, os.path.join(dist, OUT_ASCII))
    size = os.path.getsize(out)
    md5 = hashlib.md5(open(out, "rb").read()).hexdigest()

    print("[4/4] 解压回验")
    ok, msg = verify(out)
    print(f"  {'通过' if ok else '失败'}：{msg}")

    print("-" * 62)
    print(f"  {OUT_CN}")
    print(f"  {OUT_ASCII}  （内容相同，供中文名下载异常时使用）")
    print(f"  大小 {size / 1024:.1f} KB    MD5 {md5}")
    print("-" * 62)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
