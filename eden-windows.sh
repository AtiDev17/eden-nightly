#!/bin/bash -e

echo "-- Building Eden for Windows..."

# merge PGO data
if [[ "${OPTIMIZE}" == "PGO" ]]; then
    cd pgo
    chmod +x ./merge.sh
    ./merge.sh 5 3 1
    cd ..
fi

cd ./eden
COUNT="$(git rev-list --count HEAD)"

if [[ "${OPTIMIZE}" == "PGO" ]]; then
    EXE_NAME="Eden-${COUNT}-Windows-${TOOLCHAIN}-PGO-${ARCH}"
else
    EXE_NAME="Eden-${COUNT}-Windows-${TOOLCHAIN}-${ARCH}"
fi

echo "-- Build Configuration:"
echo "   Toolchain: ${TOOLCHAIN}"
echo "   Optimization: $OPTIMIZE"
echo "   Architecture: ${ARCH}"
echo "   Count: ${COUNT}"
echo "   EXE Name: ${EXE_NAME}"

# hook the updater to check my repo
echo "-- Applying updater patch..."
patch -p1 < ../patches/update.patch
echo "   Done."

# Set Base CMake flags
declare -a BASE_CMAKE_FLAGS=(
    "-DBUILD_TESTING=OFF"
    "-DDYNARMIC_TESTS=OFF"
    "-DYUZU_TESTS=OFF"
    "-DYUZU_USE_BUNDLED_QT=OFF"
    "-DYUZU_USE_BUNDLED_FFMPEG=ON"
    "-DYUZU_USE_CPM=ON"
    "-DENABLE_QT_TRANSLATION=ON"
    "-DENABLE_UPDATE_CHECKER=ON"
    "-DUSE_DISCORD_PRESENCE=ON"
    "-DYUZU_CMD=OFF"
    "-DYUZU_ROOM=ON"
    "-DYUZU_ROOM_STANDALONE=OFF"
    "-DCMAKE_BUILD_TYPE=Release"
)

# Set Extra CMake flags
declare -a EXTRA_CMAKE_FLAGS=()
case "${TOOLCHAIN}" in
    clang)
        if [[ "${OPTIMIZE}" == "PGO" ]]; then
            EXTRA_CMAKE_FLAGS+=(
                "-DCMAKE_C_COMPILER=clang-cl"
                "-DCMAKE_CXX_COMPILER=clang-cl"
                "-DCMAKE_CXX_FLAGS=-Ofast -DNOMINMAX -fprofile-use=${GITHUB_WORKSPACE}/pgo/eden.profdata -Wno-backend-plugin -Wno-profile-instr-unprofiled -Wno-profile-instr-out-of-date"
                "-DCMAKE_C_FLAGS=-Ofast -DNOMINMAX -fprofile-use=${GITHUB_WORKSPACE}/pgo/eden.profdata -Wno-backend-plugin -Wno-profile-instr-unprofiled -Wno-profile-instr-out-of-date"
            )
        else
            EXTRA_CMAKE_FLAGS+=(
                "-DCMAKE_C_COMPILER=clang-cl"
                "-DCMAKE_CXX_COMPILER=clang-cl"
                "-DCMAKE_CXX_FLAGS=-Ofast -DNOMINMAX"
                "-DCMAKE_C_FLAGS=-Ofast -DNOMINMAX"
                "-DCMAKE_C_COMPILER_LAUNCHER=ccache"
                "-DCMAKE_CXX_COMPILER_LAUNCHER=ccache"
            )
        fi
    ;;
    msys2)
        # patch to use more cpm libs
        echo "-- Applying cpm patch..."
        patch -p1 < ../patches/mingw.patch
        echo "   Done."
        
        if [[ "${OPTIMIZE}" == "PGO" ]]; then
            EXTRA_CMAKE_FLAGS+=(
                "-DYUZU_USE_EXTERNAL_SDL2=ON"
                "-DCMAKE_C_COMPILER=clang"
                "-DCMAKE_CXX_COMPILER=clang++"
                "-DCMAKE_CXX_FLAGS=-fuse-ld=lld -fprofile-use=${GITHUB_WORKSPACE}/pgo/eden.profdata -fprofile-correction -w"
                "-DCMAKE_C_FLAGS=-fuse-ld=lld -fprofile-use=${GITHUB_WORKSPACE}/pgo/eden.profdata -fprofile-correction -w"
            )
        else
            EXTRA_CMAKE_FLAGS+=(
                "-DYUZU_USE_EXTERNAL_SDL2=ON"
                "-DYUZU_ENABLE_LTO=ON"
                "-DDYNARMIC_ENABLE_LTO=ON"
                "-DCMAKE_CXX_FLAGS=-flto=auto -w"
                "-DCMAKE_C_FLAGS=-flto=auto -w"
                "-DCMAKE_C_COMPILER_LAUNCHER=ccache"
                "-DCMAKE_CXX_COMPILER_LAUNCHER=ccache"
            )
        fi
    ;;
    msvc)
        EXTRA_CMAKE_FLAGS+=(
        "-DYUZU_ENABLE_LTO=ON"
        "-DDYNARMIC_ENABLE_LTO=ON"
        "-DCMAKE_C_COMPILER_LAUNCHER=ccache"
        "-DCMAKE_CXX_COMPILER_LAUNCHER=ccache"
        )
    ;;
esac

echo "-- Base CMake flags:"
for flag in "${BASE_CMAKE_FLAGS[@]}"; do
    echo "   $flag"
done

echo "-- Extra CMake Flags:"
for flag in "${EXTRA_CMAKE_FLAGS[@]}"; do
    echo "   $flag"
done

echo "-- Starting build..."
mkdir -p build
cd build
cmake .. -G Ninja "${BASE_CMAKE_FLAGS[@]}" "${EXTRA_CMAKE_FLAGS[@]}"
ninja
echo "-- Build Completed."

echo "-- Ccache stats:"
if [[ "${OPTIMIZE}" == "normal" ]]; then
    ccache -s -v
fi

# Gather dependencies
echo "-- Gathering dependencies..."
windeployqt6 --release --no-compiler-runtime --no-opengl-sw --no-system-dxc-compiler --no-system-d3d-compiler --dir bin ./bin/eden.exe

# Recursively copy dependencies for MSYS2 builds
if [[ "${TOOLCHAIN}" == "msys2" ]]; then
    echo "-- Copying MSYS2 dependencies..."
    export PATH="/mingw64/bin:${PATH}"
    copy_deps() {
        local target="$1"
        objdump -p "$target" | awk '/DLL Name:/ {print $3}' | while read -r dll; do
            [[ -z "$dll" ]] && continue
            local dll_path
            dll_path=$(command -v "$dll" 2>/dev/null || true)
            [[ -z "$dll_path" ]] && continue

            case "$dll_path" in
                /c/Windows/System32/*|/c/Windows/SysWOW64/*) continue ;;
            esac

            local dest="./bin/$dll"
            if [[ ! -f "$dest" ]]; then
                cp -v "$dll_path" ./bin/
                copy_deps "$dll_path"
            fi
        done
    }
    copy_deps ./bin/eden.exe
    # grab deps for Qt plugins
    find ./bin/ -name "*.dll" | while read -r dll; do copy_deps "$dll"; done
fi

# Delete un-needed debug files
echo "-- Cleaning up un-needed files..."
if [[ "${TOOLCHAIN}" == "msys2" ]]; then
    find ./bin -type f \( -name "*.dll" -o -name "*.exe" \) -exec strip -s {} +
else
    find bin -type f -name "*.pdb" -exec rm -fv {} +
fi

# Pack for upload
echo "-- Packing build artifacts..."
mkdir -p artifacts
mkdir "$EXE_NAME"
cp -rv bin/* "$EXE_NAME"
ZIP_NAME="$EXE_NAME.7z"
7z a -t7z -mx=9 "$ZIP_NAME" "$EXE_NAME"
mv -v "$ZIP_NAME" artifacts/

echo "=== ALL DONE! ==="
