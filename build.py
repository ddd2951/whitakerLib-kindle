#!/usr/bin/env python3
"""Build the local KOReader package; never deploy it."""
import argparse
import hashlib
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

source = Path(__file__).resolve().parent
root = source / "whitakerLib"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--toolchain-root", type=Path, required=True,
                    help="Unpacked arm-kindlepw2-linux-gnueabi toolchain")
args = parser.parse_args()
build = source / "build"
build.mkdir(exist_ok=True)


def run(*command):
    subprocess.run([str(part) for part in command], check=True)


def compile_library(name, *options):
    directory = build / name
    run("cmake", "-S", root, "-B", directory, "-G", "Ninja", "-DCMAKE_BUILD_TYPE=Release",
        "-DWHITAKER_BUILD_TESTING=OFF", "-DWHITAKER_INSTALL=OFF", "-DWHITAKER_WERROR=OFF", *options)
    run("cmake", "--build", directory, "--target", "whitaker", "-j", "2")
    return directory / "libwhitaker.so"


for path in (source / "whitaker.koplugin").glob("*.lua"):
    run("luajit", "-b", path, build / (path.stem + ".ljc"))

header = (root / "bindings/c/whitaker.h").read_text()
start = header.index("typedef enum WhitakerPart")
end = header.index("\n#ifdef __cplusplus", start)
no_word = re.search(r"#define WHITAKER_NO_DICTIONARY_WORD (\d+)", header).group(1)
declarations = header[start:end] + f"\nstatic const int WHITAKER_NO_DICTIONARY_WORD = {no_word};\n"
arm_library = compile_library(
    "kindle", f"-DCMAKE_TOOLCHAIN_FILE={source / 'cmake/kindle.cmake'}",
    f"-DKINDLE_TOOLCHAIN_ROOT={args.toolchain_root.resolve()}",
)
package = build / "dist/whitaker.koplugin"
if package.exists():
    shutil.rmtree(package)
package.mkdir(parents=True, exist_ok=True)
for path in (source / "whitaker.koplugin").glob("*.lua"):
    shutil.copy2(path, package / path.name)
(package / "whitaker_ffi.h").write_text(declarations)
shutil.copy2(arm_library, package / "libwhitaker.so.0")
shutil.copy2(root / "LICENSE", package / "LICENSE.whitakerLib")
shutil.copy2(root / "data/source/LICENCE.txt", package / "LICENSE.WORDS")
revision = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
library = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
changed = subprocess.check_output(["git", "-C", str(source), "status", "--porcelain"], text=True).strip()
library_sum = hashlib.sha256((package / "libwhitaker.so.0").read_bytes()).hexdigest()
dictionary_sum = hashlib.sha256((root / "data/whitaker.dat").read_bytes()).hexdigest()
(package / "BUILD.txt").write_text(
    f"Built from {revision}{', with uncommitted changes' if changed else ''}, whitakerLib {library}.\n"
    f"libwhitaker.so.0 SHA-256: {library_sum}\nDictionary SHA-256: {dictionary_sum}\n"
)
archive = build / "whitaker-kindle.zip"
with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as output:
    for path in sorted(package.iterdir()):
        output.write(path, "whitaker.koplugin/" + path.name)
print(f"Package: {archive}\nPlugin directory: {package}")
