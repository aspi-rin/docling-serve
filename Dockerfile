ARG BASE_IMAGE=quay.io/sclorg/python-312-c9s:c9s

FROM ${BASE_IMAGE}

USER 0

###################################################################################################
# OS Layer                                                                                        #
###################################################################################################

RUN --mount=type=bind,source=os-packages.txt,target=/tmp/os-packages.txt \
    dnf -y install --best --nodocs --setopt=install_weak_deps=False dnf-plugins-core && \
    dnf config-manager --best --nodocs --setopt=install_weak_deps=False --save && \
    dnf config-manager --enable crb && \
    dnf -y update && \
    dnf install -y $(cat /tmp/os-packages.txt) && \
    dnf -y clean all && \
    rm -rf /var/cache/dnf

RUN /usr/bin/fix-permissions /opt/app-root/src/.cache

ENV TESSDATA_PREFIX=/usr/share/tesseract/tessdata/

###################################################################################################
# Docling layer                                                                                   #
###################################################################################################

USER 1001
WORKDIR /opt/app-root/src

ENV \
    OMP_NUM_THREADS=4 \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PYTHONIOENCODING=utf-8 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/opt/app-root \
    DOCLING_SERVE_ARTIFACTS_PATH=/opt/app-root/src/.cache/docling/models \
    QWEN3_PATH=/opt/app-root/src/.cache/docling/qwen3-32b

ARG MODEL_SRC_DIR=/tmp/empty_docling_models

ARG UV_SYNC_EXTRA_ARGS=""

RUN --mount=from=ghcr.io/astral-sh/uv:0.6.1,source=/uv,target=/bin/uv \
    --mount=type=cache,target=/opt/app-root/src/.cache/uv,uid=1001 \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    umask 002 && \
    UV_SYNC_ARGS="--frozen --no-install-project --no-dev --all-extras" && \
    uv sync ${UV_SYNC_ARGS} ${UV_SYNC_EXTRA_ARGS} --no-extra flash-attn && \
    FLASH_ATTENTION_SKIP_CUDA_BUILD=TRUE uv sync ${UV_SYNC_ARGS} ${UV_SYNC_EXTRA_ARGS} --no-build-isolation-package=flash-attn

################################################################################
# 复制宿主机模型（替代在线下载）                                                #
################################################################################
# 说明：需要 BuildKit 支持（Docker 23.x 默认开启；经典 docker 请先 export DOCKER_BUILDKIT=1）
RUN --mount=type=bind,from=models_ctx,target=/tmp/host_models,ro \
    mkdir -p "${DOCLING_SERVE_ARTIFACTS_PATH}" && \
    cp -R /tmp/host_models/docling-models/* "${DOCLING_SERVE_ARTIFACTS_PATH}" && \
    chown -R 1001:0 "${DOCLING_SERVE_ARTIFACTS_PATH}" && \
    chmod -R g=u "${DOCLING_SERVE_ARTIFACTS_PATH}" &&\
    mkdir -p "${QWEN3_PATH}" && \
    cp -R /tmp/host_models/qwen3-32b/* "${QWEN3_PATH}" && \
    chown -R 1001:0 "${QWEN3_PATH}" && \
    chmod -R g=u "${QWEN3_PATH}"


COPY --chown=1001:0 ./docling_serve ./docling_serve
RUN --mount=from=ghcr.io/astral-sh/uv:0.6.1,source=/uv,target=/bin/uv \
    --mount=type=cache,target=/opt/app-root/src/.cache/uv,uid=1001 \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    umask 002 && \
    uv sync --frozen --no-dev --all-extras ${UV_SYNC_EXTRA_ARGS}

EXPOSE 5001
CMD ["docling-serve", "run"]
