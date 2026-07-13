# syntax=docker/dockerfile:1
# ---------------------------------------------------------------------------
# Marzban panel - Railway deploy wrapper (Unified Builder for Railway Limits)
# ---------------------------------------------------------------------------

ARG PYTHON_VERSION=3.12

# --------------------------------------------------------
# Stage 1: Unified Builder (Frontend + Backend + Xray)
# --------------------------------------------------------
FROM python:${PYTHON_VERSION}-slim AS builder

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    DEBIAN_FRONTEND=noninteractive

# نصب یکپارچه پیش‌نیازهای پایتون، نود جی‌اس و ابزارهای سیستمی
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential gcc python3-dev libpq-dev git curl unzip ca-certificates gnupg \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

ARG MARZBAN_REPO=https://github.com/Gozargah/Marzban.git
ARG MARZBAN_REF=master
RUN git clone --depth 1 --branch ${MARZBAN_REF} ${MARZBAN_REPO} .

# نصب ایمن Xray-core
RUN curl -sL https://github.com/Gozargah/Marzban-scripts/raw/master/install_latest_xray.sh -o /tmp/install_xray.sh \
    && bash /tmp/install_xray.sh \
    && rm -f /tmp/install_xray.sh

# بیلد کردن داشبورد React/Vite
RUN cd app/dashboard \
    && npm install --no-audit --no-fund \
    && VITE_BASE_API=/api/ npm run build --if-present -- --outDir build --assetsDir statics \
    && cp build/index.html build/404.html \
    && cd ../..

# نصب وابستگی‌های پایتون
RUN python3 -m pip install --upgrade pip setuptools wheel \
    && pip install --no-cache-dir -r requirements.txt

# ---------------------------------------------------------------------------
# Stage 2: Runtime Image
# ---------------------------------------------------------------------------
FROM python:${PYTHON_VERSION}-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHON_LIB_PATH=/usr/local/lib/python3.12/site-packages \
    XRAY_EXECUTABLE_PATH=/usr/local/bin/xray \
    XRAY_ASSETS_PATH=/usr/local/share/xray \
    SQLALCHEMY_DATABASE_URL=sqlite:////code/db.sqlite3 \
    TZ=UTC

WORKDIR /code

RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq5 ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# کپی پکیج‌های پایتون
COPY --from=builder $PYTHON_LIB_PATH $PYTHON_LIB_PATH

# بهبود [Critical]: کپی کردن پوشه bin برای استخراج دستورات uvicorn، alembic و xray
# (ابزارهای node و npm در /usr/bin/ هستند، پس نگران کپی شدن آن‌ها نباشید)
COPY --from=builder --chown=appuser:appuser /usr/local/bin /usr/local/bin

# کپی فایل‌های Xray و سورس کد
COPY --from=builder --chown=appuser:appuser /usr/local/share/xray /usr/local/share/xray
COPY --from=builder --chown=appuser:appuser /build /code

# رفع مشکل setuptools
RUN pip install --no-cache-dir "setuptools==75.8.0"

COPY --chown=appuser:appuser start-railway.sh /code/start-railway.sh

RUN useradd -m -u 1000 appuser \
    && mkdir -p /code/data /var/lib/marzban \
    && chown -R appuser:appuser /code /var/lib/marzban \
    && ln -sf /code/marzban-cli.py /usr/local/bin/marzban-cli \
    && chmod +x /usr/local/bin/marzban-cli /code/start-railway.sh

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=5 \
    CMD curl -fsS "http://127.0.0.1:${PORT:-8000}/" || exit 1

ENTRYPOINT ["bash", "/code/start-railway.sh"]
