# syntax=docker/dockerfile:1

# ---------- Build frontend ----------
ARG BUILD_HASH=dev-build
FROM --platform=$BUILDPLATFORM node:current-alpine3.20 AS build
ARG BUILD_HASH
WORKDIR /app

# Add memory allocation for Node.js build
ENV NODE_OPTIONS=--max-old-space-size=8192

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
ENV APP_BUILD_HASH=${BUILD_HASH}
RUN npm run build

# ---------- Base container (Arch + ROSE + paru) ----------
FROM archlinux:base-devel AS base

ARG UID=0
ARG GID=0
ARG USE_CUDA=true
ARG USE_ROSE=true
ARG USE_CUDA_VER=cu126
ARG USE_EMBEDDING_MODEL=sentence-transformers/all-MiniLM-L6-v2
ARG USE_RERANKING_MODEL=intfloat/multilingual-e5-base

ENV ENV=prod \
    PORT=8080 \
    USE_ROSE_DOCKER=${USE_ROSE} \
    USE_CUDA_DOCKER=${USE_CUDA} \
    USE_CUDA_DOCKER_VER=${USE_CUDA_VER} \
    USE_EMBEDDING_MODEL_DOCKER=${USE_EMBEDDING_MODEL} \
    USE_RERANKING_MODEL_DOCKER=${USE_RERANKING_MODEL} \
    ROSE_BASE_URL="/rose" \
    OPENAI_API_BASE_URL="" \
    OPENAI_API_KEY="" \
    WEBUI_SECRET_KEY="" \
    SCARF_NO_ANALYTICS=true \
    DO_NOT_TRACK=true \
    ANONYMIZED_TELEMETRY=false \
    WHISPER_MODEL="base" \
    WHISPER_MODEL_DIR="/app/backend/data/cache/whisper/models" \
    RAG_EMBEDDING_MODEL="$USE_EMBEDDING_MODEL_DOCKER" \
    RAG_RERANKING_MODEL="$USE_RERANKING_MODEL_DOCKER" \
    SENTENCE_TRANSFORMERS_HOME="/app/backend/data/cache/embedding/models" \
    TIKTOKEN_ENCODING_NAME="cl100k_base" \
    TIKTOKEN_CACHE_DIR="/app/backend/data/cache/tiktoken" \
    HF_HOME="/app/backend/data/cache/embedding/models" \
    TORCH_EXTENSIONS_DIR="/app/backend/data/cache/torch_extensions" \
    HOME="/root"

WORKDIR /app/backend

RUN if [ "$UID" -ne 0 ]; then \
    if [ "$GID" -ne 0 ]; then groupadd --gid "$GID" app; fi && \
    useradd --uid "$UID" --gid "$GID" --home "$HOME" --no-create-home app; \
    fi

RUN mkdir -p $HOME/.cache/chroma && \
    echo -n 00000000-0000-0000-0000-000000000000 > $HOME/.cache/chroma/telemetry_user_id && \
    chown -R $UID:$GID /app $HOME

RUN pacman -Sy --noconfirm && \
    sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf && \
    pacman -Syyu --noconfirm && \
    pacman -S --noconfirm git base-devel sudo curl jq ffmpeg opencv python python-pip gcc make pandoc openbsd-netcat rsync

# Add paru and AUR support
RUN useradd -m builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder && \
    chown -R builder:builder /home/builder

USER builder
WORKDIR /home/builder
RUN git clone https://aur.archlinux.org/paru.git && cd paru && makepkg -si --noconfirm
USER root

# Install ROSE binary (or use Ollama if ROSE binary not available)
RUN if [ "$USE_ROSE" = "true" ]; then \
    curl -fsSL https://ollama.com/install.sh | sh && \
    mv /usr/bin/ollama /usr/bin/rose && \
    chmod +x /usr/bin/rose; \
    fi

# Python deps
COPY --chown=$UID:$GID ./backend/requirements.txt ./requirements.txt

RUN pip3 install uv && \
    if [ "$USE_CUDA" = "true" ]; then \
    pacman -S --noconfirm cuda && \
    pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/$USE_CUDA_VER --no-cache-dir && \
    uv pip install --system -r requirements.txt --no-cache-dir && \
    python -c "import os; from sentence_transformers import SentenceTransformer; SentenceTransformer(os.environ['RAG_EMBEDDING_MODEL'], device='cpu')" && \
    python -c "import os; from faster_whisper import WhisperModel; WhisperModel(os.environ['WHISPER_MODEL'], device='cpu', compute_type='int8', download_root=os.environ['WHISPER_MODEL_DIR'])" && \
    python -c "import os; import tiktoken; tiktoken.get_encoding(os.environ['TIKTOKEN_ENCODING_NAME'])"; \
    else \
    pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu --no-cache-dir && \
    uv pip install --system -r requirements.txt --no-cache-dir && \
    python -c "import os; from sentence_transformers import SentenceTransformer; SentenceTransformer(os.environ['RAG_EMBEDDING_MODEL'], device='cpu')" && \
    python -c "import os; from faster_whisper import WhisperModel; WhisperModel(os.environ['WHISPER_MODEL'], device='cpu', compute_type='int8', download_root=os.environ['WHISPER_MODEL_DIR'])" && \
    python -c "import os; import tiktoken; tiktoken.get_encoding(os.environ['TIKTOKEN_ENCODING_NAME'])"; \
    fi

# Copy frontend and backend
COPY --chown=$UID:$GID --from=build /app/build /app/build
COPY --chown=$UID:$GID --from=build /app/CHANGELOG.md /app/CHANGELOG.md
COPY --chown=$UID:$GID --from=build /app/package.json /app/package.json
COPY --chown=$UID:$GID ./backend .

EXPOSE 8080

HEALTHCHECK CMD curl --silent --fail http://localhost:${PORT:-8080}/health | jq -ne 'input.status == true' || exit 1

USER $UID:$GID

ARG BUILD_HASH
ENV WEBUI_BUILD_VERSION=${BUILD_HASH}
ENV DOCKER=true

CMD ["bash", "start.sh"]

