#!/bin/bash
# Check a built container against its version's recipe, as CI does after
# every build and before any publish (.github/workflows/containers.yml):
#
#   [DISPLAY=<X display open to any client>] envs/check-container.sh <local name> <env>/<n>
#
# CI passes its own Xvfb's DISPLAY. With no DISPLAY, or in WSL, which has
# no Xvfb, a napari version's checks start one in a throwaway container
# and remove it on exit (envs/README.md's Building on the desktop).
#
# Fails, naming what is wrong, unless:
#   - pip freeze inside it is envs/<env>/<n>/requirements.lock exactly
#   - every package in the lock imports (check_imports.py)
# for a version whose lock pins torch:
#   - PyTorch is compiled for sm_70, as the V100s need
# and, for a version whose lock pins napari (iris-view):
#   - the lock pins one Qt binding, PyQt5 or PyQt6
#   - that binding's xcb platform plugin, its GLX integration and the
#     modules napari loads find every library they link
#   - napari draws a frame on $DISPLAY, which Xvfb -ac provides in CI;
#     offscreen Qt has no OpenGL and draws nothing
# Needs Docker.

set -euo pipefail

NAME="${1:?usage: envs/check-container.sh <local name> <env>/<n>}"
VERSION="${2:?usage: envs/check-container.sh <local name> <env>/<n>}"
ENVS="$(cd "$(dirname "$0")" && pwd)"
LOCK="$ENVS/$VERSION/requirements.lock"
[ -f "$LOCK" ] || { echo "No $LOCK."; exit 1; }

# Until Docker Desktop runs, its WSL docker isn't there and PATH reaches
# Windows docker.exe, which can't mount a WSL path.
case "$(command -v docker)" in
    /mnt/*) echo "FAILED: docker is $(command -v docker), Windows' own, which can't mount WSL paths; start Docker Desktop, whose WSL docker is /usr/bin/docker."; exit 1 ;;
esac

# The Qt binding napari draws with is whichever one the lock pins, read
# before any Docker run so a lock with neither fails at once.
QT=
if grep -qiE '^napari==' "$LOCK"; then
    # Each binding pinned, by its name before ==, any case, written PyQt5 or PyQt6.
    pinned=$(sed -nE 's/^pyqt([56])[[:space:]]*==.*/PyQt\1/Ip' "$LOCK" | sort -u | tr '\n' ' ')
    case "$pinned" in
        "PyQt5 "|"PyQt6 ") QT="${pinned% }" ;;
        "") echo "FAILED: envs/$VERSION/requirements.lock pins napari but neither PyQt5 nor PyQt6."; exit 1 ;;
        *) echo "FAILED: envs/$VERSION/requirements.lock pins both PyQt5 and PyQt6; pin one."; exit 1 ;;
    esac
fi

# The X socket folder the checks mount: the host's, or the throwaway
# Xvfb's volume.
x11_src=/tmp/.X11-unix

in_container() {
    docker run --rm -v "$ENVS:/recipe:ro" -v "$x11_src:/tmp/.X11-unix" \
        -e DISPLAY -e MLFLOW_DISABLE_AGENT_HINT=1 "$NAME" "$@"
}

echo "== installed packages against $VERSION's requirements.lock"
if ! diff <(tr -d '\r' < "$LOCK") <(in_container python -m pip freeze); then
    echo "FAILED: the installed packages differ from envs/$VERSION/requirements.lock (diff above)."
    exit 1
fi
echo "identical"

echo "== imports"
in_container python /recipe/check_imports.py "/recipe/$VERSION/requirements.lock"

if grep -qiE '^torch==' "$LOCK"; then
    echo "== PyTorch compiled for the V100s (sm_70)"
    in_container python -c 'import torch; a = torch._C._cuda_getArchFlags(); print(a); assert "sm_70" in a.split(), "no sm_70: this PyTorch cannot run on the V100s"'
else
    echo "No torch in the lock, so no GPU arch check."
fi

if [ -z "$QT" ]; then
    echo "No napari in the lock, so no Qt or drawing checks."
    echo "Container checks passed."
    exit 0
fi

# WSL's own DISPLAY, WSLg's :0, is a socket Docker Desktop's containers
# can't reach, so WSL always takes the throwaway Xvfb.
if [ -z "${DISPLAY:-}" ] || [ -n "${WSL_DISTRO_NAME:-}" ]; then
    x11_src="iris-check-x11-$$"
    xvfb="iris-check-xvfb-$$"
    trap 'docker rm -f "$xvfb" >/dev/null 2>&1; docker volume rm "$x11_src" >/dev/null 2>&1' EXIT
    echo "== Xvfb in a throwaway container ($xvfb)"
    docker run -d --name "$xvfb" -v "$x11_src:/tmp/.X11-unix" debian:bookworm-slim sh -c \
        'apt-get update -q >/dev/null && apt-get install -yq xvfb >/dev/null && exec Xvfb :99 -ac -screen 0 1280x1024x24' >/dev/null
    up=
    for _ in $(seq 60); do
        if docker exec "$xvfb" test -S /tmp/.X11-unix/X99 2>/dev/null; then up=1; break; fi
        if [ "$(docker inspect -f '{{.State.Running}}' "$xvfb")" != true ]; then
            docker logs "$xvfb"
            echo "FAILED: Xvfb's container $xvfb stopped (its log above)."
            exit 1
        fi
        sleep 5
    done
    [ -n "$up" ] || { echo "FAILED: Xvfb in $xvfb made no display in 5 minutes."; exit 1; }
    export DISPLAY=:99
fi

case "$QT" in
    PyQt5) modules="Core Gui Widgets OpenGL Svg" ;;
    PyQt6) modules="Core Gui Widgets OpenGL OpenGLWidgets Svg" ;;
esac

echo "== Qt libraries ($QT)"
# shellcheck disable=SC2016  # expanded inside the container
missing=$(in_container bash -c 'b=$1; q=$(python -c "import os, $b; print(os.path.dirname($b.__file__))")
    libs=(); for m in $2; do libs+=("$q/Qt$m.abi3.so"); done
    ldd "${libs[@]}" "$q/Qt${b#PyQt}/plugins/platforms/libqxcb.so" \
        "$q/Qt${b#PyQt}"/plugins/xcbglintegrations/*.so | grep "not found" | sort -u' _ "$QT" "$modules")
if [ -n "$missing" ]; then
    echo "$missing"
    echo "FAILED: Qt can't find the libraries above; add their Debian packages to envs/$VERSION/Dockerfile, the version's own beside its lock, since a published Dockerfile is never edited."
    exit 1
fi
echo "all found"

echo "== napari draws a frame"
in_container python -c '
import numpy as np, napari
from vispy.gloo import gl
v = napari.Viewer(show=False)
v.add_image(np.random.rand(64, 64))
v.add_labels(np.ones((64, 64), dtype=np.uint8))
shot = v.screenshot(canvas_only=True, flash=False)
assert shot.size and shot.any(), "napari drew an empty frame"
print("napari", napari.__version__, "drew", shot.shape, "with", gl.glGetParameter(gl.GL_RENDERER))
v.close()'

echo "Container checks passed."
