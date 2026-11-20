# A later version of an environment, <env>/<n> for n > 1, that carries no
# Dockerfile of its own and whose lock keeps every line of the lock before
# it (envs/build-kind.sh prints "layer"): the version before it, pulled by
# digest, plus the packages <env>/<n>'s lock adds, as one new layer. The
# registry stores the layers the two share only once. pip installs only what
# is new: every other line is already satisfied. Any other version is built
# fresh, from the Dockerfile envs/build-kind.sh names (ADR-0010).
#
# Once a layer version is published, this file is never edited beyond its
# comments and blank lines, which bin/check holds it to (#241), since every
# published layer was built from it. A version that needs another layer
# recipe carries its own Dockerfile, beside its lock, and is built fresh
# from it.
#
# envs/build-container.sh <env>/<n> builds it, with envs/<env>/<n>/ as the
# context and PREVIOUS the version before it by digest alone
# (ghcr.io/unsw-restech/iris-env@sha256:<hex>), from lib/katana.sh's
# digest map.

ARG PREVIOUS
FROM ${PREVIOUS}

COPY requirements.lock /opt/iris-build/requirements.lock
RUN pip install --no-cache-dir --only-binary=:all: --no-deps \
        --extra-index-url https://download.pytorch.org/whl/cu128 \
        -r /opt/iris-build/requirements.lock \
    && rm -r /opt/iris-build

ARG VERSION=unknown
ARG COMMIT=unknown
LABEL org.opencontainers.image.revision=$COMMIT \
      org.opencontainers.image.version=$VERSION
