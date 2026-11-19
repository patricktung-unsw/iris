#!/bin/bash
# bin/check's environment versions check against throwaway trees, each with
# its own copy of bin/check and lib/katana.sh: the digest map and lab table
# in lib/katana.sh are well formed and match envs/, every form pins a
# version in the digest map, and a later version of an environment may add,
# change or remove packages: envs/build-kind.sh calls one that only adds a
# layer and any other, or one carrying its own Dockerfile, fresh from the
# nearest Dockerfile, and bin/check notes why. Prints each
# failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_env_versions.sh
#
# bin/check name: environment versions test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

name="environment versions match the digest map"
digest=sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef

# make_tree <name>: a site with a seg workflow in the microct-lab section,
# lib/katana.sh's digest map holding microct/1 unpublished, its lab table
# starting microct-lab on it and the researcher tools on it too, and
# microct/1's lock and Dockerfile.
make_tree() {
    local tree="$scratch/$1"
    site_tree "$tree" seg:microct-lab:active
    mkdir -p "$tree/lib" "$tree/envs/microct/1"
    cp lib/katana.sh "$tree/lib/katana.sh"
    cp envs/build-kind.sh "$tree/envs/build-kind.sh"
    digest_map "$tree/lib/katana.sh" --tools microct/1 microct/1=unpublished || exit 1
    sed -i '/^declare -gA IRIS_LAB_ENVS=(/,/^)/c\declare -gA IRIS_LAB_ENVS=(\n    [microct-lab]=microct/1\n)' \
        "$tree/lib/katana.sh"
    printf '%s\n' 'numpy==2.3.0' 'xarray==2025.6.1' > "$tree/envs/microct/1/requirements.lock"
    printf '%s\n' 'FROM python:3.12-slim' > "$tree/envs/microct/1/Dockerfile"
    git -C "$tree" add -A
}

# dockerfile <tree> <env>/<n>: the version carries its own Dockerfile.
dockerfile() {
    printf '%s\n' 'FROM python:3.13-slim' > "$scratch/$1/envs/$2/Dockerfile"
    git -C "$scratch/$1" add -A
}

# add_version <tree> <env>/<n> <digest> <lock line>...: a version in the
# digest map with a lock of the lines given.
add_version() {
    local tree="$scratch/$1" version="$2" value="$3"
    shift 3
    digest_map_add "$tree/lib/katana.sh" "$version=$value" || exit 1
    mkdir -p "$tree/envs/$version"
    printf '%s\n' "$@" > "$tree/envs/$version/requirements.lock"
    git -C "$tree" add -A
}

# edit <tree> <file> <sed script>
edit() {
    sed -i "$3" "$scratch/$1/$2"
    git -C "$scratch/$1" add -A
}

# pin <tree> <version>: the seg form pins <version>.
pin() {
    printf '%s\n' 'script: |' '  #!/bin/bash' '  #PBS -A iris-seg' "  IRIS_ENV_VERSION=$2" \
        > "$scratch/$1/workflows/seg/form.yml.erb"
    git -C "$scratch/$1" add -A
}

make_tree clean
expect pass "$scratch/clean" "$name"

# The repo's own lib/katana.sh and envs/ pass.
make_tree repo
cp lib/katana.sh "$scratch/repo/lib/katana.sh"
rm -rf "$scratch/repo/envs"
cp -r envs "$scratch/repo/envs"
git -C "$scratch/repo" add -A
expect pass "$scratch/repo" "$name"

make_tree published
edit published lib/katana.sh "s|\[microct/1\]=unpublished|[microct/1]=$digest|"
expect pass "$scratch/published" "$name"

make_tree crlf
edit crlf lib/katana.sh 's/$/\r/'
expect pass "$scratch/crlf" "$name"

# A digest is sha256:<64 hex> or unpublished, nothing else.
make_tree short-digest
edit short-digest lib/katana.sh 's|\[microct/1\]=unpublished|[microct/1]=sha256:0123abcd|'
expect fail "$scratch/short-digest" "$name"
make_tree tag-and-digest
edit tag-and-digest lib/katana.sh "s|\[microct/1\]=unpublished|[microct/1]=microct-1@$digest|"
expect fail "$scratch/tag-and-digest" "$name"
make_tree todo
edit todo lib/katana.sh 's|\[microct/1\]=unpublished|[microct/1]=TODO|'
expect fail "$scratch/todo" "$name"
# An author's version, published by CI on their fork, is its container in
# their own account by digest, until the review batch copies it into the
# org's package (#138); the org's own is written as its digest alone.
make_tree author
add_version author microct/2 "ghcr.io/an-author/iris-env@$digest" 'numpy==2.3.0' 'scipy==1.16.0' 'xarray==2025.6.1'
expect pass "$scratch/author" "$name"
make_tree author-short
add_version author-short microct/2 "ghcr.io/an-author/iris-env@sha256:0123abcd" 'numpy==2.3.0' 'xarray==2025.6.1'
expect fail "$scratch/author-short" "$name"
make_tree author-other-package
add_version author-other-package microct/2 "ghcr.io/an-author/other@$digest" 'numpy==2.3.0' 'xarray==2025.6.1'
expect fail "$scratch/author-other-package" "$name"
make_tree author-upper
add_version author-upper microct/2 "ghcr.io/An-Author/iris-env@$digest" 'numpy==2.3.0' 'xarray==2025.6.1'
expect fail "$scratch/author-upper" "$name"
make_tree org-in-full
edit org-in-full lib/katana.sh "s|\[microct/1\]=unpublished|[microct/1]=ghcr.io/unsw-restech/iris-env@$digest|"
expect fail "$scratch/org-in-full" "$name"

# Versions are <env>/<n> counting from 1, each with its recipe in envs/.
make_tree bad-name
add_version bad-name microct/v2 unpublished 'numpy==2.3.0' 'xarray==2025.6.1'
expect fail "$scratch/bad-name" "$name"
make_tree no-lock
rm "$scratch/no-lock/envs/microct/1/requirements.lock"
git -C "$scratch/no-lock" add -A
expect fail "$scratch/no-lock" "$name"
make_tree lock-not-in-map
mkdir -p "$scratch/lock-not-in-map/envs/microct/2"
printf '%s\n' 'numpy==2.3.0' > "$scratch/lock-not-in-map/envs/microct/2/requirements.lock"
git -C "$scratch/lock-not-in-map" add -A
expect fail "$scratch/lock-not-in-map" "$name"
make_tree gap
add_version gap microct/3 unpublished 'numpy==2.3.0' 'xarray==2025.6.1'
expect fail "$scratch/gap" "$name"

# The lab table names labs of the catalogue and versions in the digest map;
# labs may share an environment.
make_tree shared
sed -i 's|<div class="lab" id="microct-lab">|<div class="lab" id="bril"></div>\n  &|' "$scratch/shared/index.html"
edit shared lib/katana.sh '/^    \[microct-lab\]=/a\    [bril]=microct/1'
expect pass "$scratch/shared" "$name"
make_tree lab-version-missing
edit lab-version-missing lib/katana.sh 's|\[microct-lab\]=microct/1|[microct-lab]=microct/2|'
expect fail "$scratch/lab-version-missing" "$name"
make_tree unknown-lab
edit unknown-lab lib/katana.sh 's|\[microct-lab\]=|[ct-lab]=|'
expect fail "$scratch/unknown-lab" "$name"

# A form pins a version in the digest map, published or not yet.
make_tree pinned
pin pinned microct/1
expect pass "$scratch/pinned" "$name"
make_tree pinned-missing
pin pinned-missing microct/2
expect fail "$scratch/pinned-missing" "$name"
# The researcher tools run in a version in the digest map too.
make_tree tools-missing
edit tools-missing lib/katana.sh 's|^IRIS_TOOLS_ENV_VERSION=.*|IRIS_TOOLS_ENV_VERSION=microct/2|'
expect fail "$scratch/tools-missing" "$name"

# A later version may add, change or remove packages (ADR-0010). One that
# carries no Dockerfile and keeps every line of the lock before it is a
# layer on it; any other, and a first version, is built fresh, from the
# Dockerfile of the nearest version at or before it that has one.
# bin/check notes a version that changes pins, naming the packages, or
# carries its own Dockerfile, without failing it.
# kind <tree> <version> <want>: envs/build-kind.sh's first line is <want>.
kind() {
    local got
    got="$("$scratch/$1/envs/build-kind.sh" "$2" 2>&1 | head -n1)"
    [ "$got" = "$3" ] || echo "$1: envs/build-kind.sh $2 printed '$got', expected $3"
}
# note <tree> <pattern>: bin/check's output has a NOTE line matching it.
note() {
    local out
    out="$("$scratch/$1/bin/check" "$name" 2>&1)"
    grep -qE "^NOTE: .*$2" <<< "$out" ||
        { echo "$1: no NOTE line matching '$2'"; echo "$out" | sed 's/^/  /'; }
}
kind clean microct/1 'fresh envs/microct/1/Dockerfile'
make_tree adds
add_version adds microct/2 unpublished 'numpy==2.3.0' 'scipy==1.16.0' 'xarray==2025.6.1'
expect pass "$scratch/adds" "$name"
kind adds microct/2 layer
out="$("$scratch/adds/bin/check" "$name" 2>&1)"
! grep -q '^NOTE: ' <<< "$out" || { echo "adds: a NOTE for a version that only adds"; echo "$out" | sed 's/^/  /'; }
make_tree removes
add_version removes microct/2 unpublished 'numpy==2.3.0' 'scipy==1.16.0'
expect pass "$scratch/removes" "$name"
kind removes microct/2 'fresh envs/microct/1/Dockerfile'
note removes 'microct/2 removes xarray==2025\.6\.1.*built fresh'
make_tree changes
add_version changes microct/2 unpublished 'numpy==2.3.1' 'xarray==2025.6.1'
expect pass "$scratch/changes" "$name"
kind changes microct/2 'fresh envs/microct/1/Dockerfile'
note changes 'microct/2 changes numpy==2\.3\.0 to numpy==2\.3\.1.*built fresh'
make_tree both
add_version both microct/2 unpublished 'NumPy==2.3.1 # pinned' 'scipy==1.16.0'
expect pass "$scratch/both" "$name"
note both 'changes numpy==2\.3\.0 to NumPy==2\.3\.1 and removes xarray==2025\.6\.1'
# The version after a fresh one that only adds is a layer on it.
make_tree after-fresh
add_version after-fresh microct/2 unpublished 'numpy==2.3.1' 'xarray==2025.6.1'
add_version after-fresh microct/3 unpublished 'numpy==2.3.1' 'scipy==1.16.0' 'xarray==2025.6.1'
kind after-fresh microct/3 layer
# A version that carries its own Dockerfile is built fresh from it, even
# when its lock only adds, and bin/check notes why.
make_tree own
add_version own microct/2 unpublished 'numpy==2.3.0' 'scipy==1.16.0' 'xarray==2025.6.1'
dockerfile own microct/2
expect pass "$scratch/own" "$name"
kind own microct/2 'fresh envs/microct/2/Dockerfile'
note own 'microct/2 carries its own Dockerfile.*built fresh'
# A later version built fresh without its own Dockerfile builds from the
# nearest version at or before it that has one, so microct/3, which changes
# a pin, keeps what microct/2's Dockerfile added; one that only adds is
# still a layer.
make_tree nearest
add_version nearest microct/2 unpublished 'numpy==2.3.0' 'scipy==1.16.0' 'xarray==2025.6.1'
dockerfile nearest microct/2
add_version nearest microct/3 unpublished 'numpy==2.3.1' 'scipy==1.16.0' 'xarray==2025.6.1'
add_version nearest microct/4 unpublished 'numpy==2.3.1' 'scipy==1.16.0' 'tifffile==2025.6.11' 'xarray==2025.6.1'
expect pass "$scratch/nearest" "$name"
kind nearest microct/3 'fresh envs/microct/2/Dockerfile'
kind nearest microct/4 layer
note nearest 'microct/3 changes numpy==2\.3\.0 to numpy==2\.3\.1.*built fresh'
# With no later Dockerfile, a fresh version builds from the first version's.
make_tree first
add_version first microct/2 unpublished 'numpy==2.3.0' 'scipy==1.16.0' 'xarray==2025.6.1'
add_version first microct/3 unpublished 'numpy==2.3.1' 'scipy==1.16.0' 'xarray==2025.6.1'
kind first microct/3 'fresh envs/microct/1/Dockerfile'
