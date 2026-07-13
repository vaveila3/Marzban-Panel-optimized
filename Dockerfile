# syntax=docker/dockerfile:1
# ---------------------------------------------------------------------------
# Marzban panel - Railway deploy wrapper (Optimized 3-Stage Production Build)
# ---------------------------------------------------------------------------

# --------------------------------------------------------
# Stage 1: Build Frontend (React/Vite)
# استفاده از ایمج رسمی نود جی‌اس برای جلوگیری از curl|bash
# --------------------------------------------------------
FROM node:20-slim AS frontend-builder

WORKDIR /build
ARG MARZBAN_REPO=https://github.com/Gozargah/Marzban.git
ARG MARZBAN_REF=master

# فقط کلون کردن برای استخراج پوشه داشبورد (عمق ۱ برای سرعت)
RUN apt-get update && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/* \
    && git clone --depth 1 --branch ${MARZBAN_REF} ${MARZBAN_REPO} .

RUN cd app/dashboard \
    && npm install --no-audit --no-fund \
    && VITE_BASE_API=/api/ npm run build --if-present -- --outDir build --assetsDir statics \
    && cp build/index.html build/404.html

# --------------------------------------------------------
# Stage 2: Python Builder
# --------------------------------------------------------
FROM python:3.12-slim AS builder

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential gcc python3-dev libpq-dev git curl unzip ca-certificates jq \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

ARG MARZBAN_REPO=https://github.com/Gozargah/Marzban.git
ARG MARZBAN_REF=master
RUN git clone --depth 1 --branch ${MARZBAN_REF} ${MARZBAN_REPO} .

# بهبود [Critical]: دانلود امن باینری Xray بدون اجرای مستقیم اسکریپت‌های بیگانه
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then DL_ARCH="amd64"; \
    elif [ "$ARCH" = "aarch64" ]; then DL_ARCH="arm64-v8a"; \
    else DL_ARCH="$ARCH"; fi && \
    LATEST_URL=$(curl -sL https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r '.assets[] | select(.name | contains("linux-'"$DL_ARCH"'")) | .browser_download_url') && \
    curl -Lo /tmp/xray.zip "$LATEST_URL" && \
    mkdir -p /usr/local/share/xray && \
    unzip -o /tmp/xray.zip -d /usr/local/share/xray && \
    mv /usr/local/share/xray/xray /usr/local/bin/xray && \
    chmod +x /usr/local/bin/xray && \
    rm -rf /tmp/xray.zip

# کپی کردن فایل‌های بیلد شده از Stage 1 به پوشه داشبورد
COPY --from=frontend-builder /build/app/dashboard/build /build/app/dashboard/build

RUN python3 -m pip install --upgrade pip setuptools wheel \
    && pip install --no-cache-dir -r requirements.txt

# --------------------------------------------------------
# Stage 3: Runtime Image
# --------------------------------------------------------
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHON_LIB_PATH=/usr/local/lib/python3.12/site-packages \
    XRAY_EXECUTABLE_PATH=/usr/local/bin/xray \
    XRAY_ASSETS_PATH=/usr/local/share/xray \
    SQLALCHEMY_DATABASE_URL=sqlite:////code/db.sqlite3 \
    TZ=UTC

WORKDIR /code

# فقط نصب کتابخانه‌های رانتایم (نیازی به gcc و ابزارهای بیلد نیست)
RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq5 ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# بهبود [High]: کپی دقیق پکیج‌های پایتون (جلوگیری از کپی کردن node، npm و git)
COPY --from=builder $PYTHON_LIB_PATH $PYTHON_LIB_PATH

# کپی دقیق باینری Xray و فایل‌های مرتبط
COPY --from=builder --chown=appuser:appuser /usr/local/bin/xray /usr/local/bin/xray
COPY --from=builder --chown=appuser:appuser /usr/local/share/xray /usr/local/share/xray

# کپی سورس کد پنل
COPY --from=builder --chown=appuser:appuser /build /code

# رفع مشکل setuptools
RUN pip install --no-cache-dir "setuptools==75.8.0"

COPY --chown=appuser:appuser start-railway.sh /code/start-railway.sh

# ایجاد یوزر و لینک کردن CLI
RUN useradd -m -u
