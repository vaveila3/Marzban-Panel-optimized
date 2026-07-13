#!/usr/bin/env bash
# Railway entrypoint for Marzban panel.
set -euo pipefail

# حذف cd /code به دلیل تنظیم WORKDIR در داکرفایل

export HOST="0.0.0.0"
export PORT="${PORT:-8000}"
export UVICORN_HOST="$HOST"
export UVICORN_PORT="$PORT"
export SQLALCHEMY_DATABASE_URL="${SQLALCHEMY_DATABASE_URL:-sqlite:////code/db.sqlite3}"

echo "==> [railway] Marzban panel starting on ${HOST}:${PORT}"

echo "==> [railway] Running database migrations (alembic upgrade head)..."
if ! alembic upgrade head; then
    echo "!! [railway] alembic upgrade failed; falling back to create_all()..."
    python -c "
import app.db.base as b
try:
    b.Base.metadata.create_all(bind=b.engine)
    print('create_all() succeeded')
except Exception as e:
    print('create_all() also failed:', e)
    exit(1)
"
fi

if [ -n "${SUDO_USERNAME:-}" ] && [ -n "${SUDO_PASSWORD:-}" ]; then
    echo "==> [railway] Ensuring sudo admin '${SUDO_USERNAME}' exists..."
    # اضافه شدن 2> /dev/null برای پاکسازی لاگ‌های خطای غیرضروری در صورت وجود داشتن ادمین
    if python create_admin.py --username "$SUDO_USERNAME" --password "$SUDO_PASSWORD" --sudo 2>/dev/null; then
        echo "==> [railway] Admin created successfully."
    else
        echo "==> [railway] Admin already exists or creation skipped."
    fi
else
    echo "==> [railway] SUDO_USERNAME / SUDO_PASSWORD not set."
    echo "    Create an admin later from the Railway console with:"
    echo "    marzban-cli admin create --sudo"
fi

echo "==> [railway] Launching uvicorn..."
# استفاده از --workers 1 کاملاً هوشمندانه است چون SQLite در ریلوی با Concurrency بالا قفل می‌شود (Database Locked)
exec uvicorn main:app \
    --host "$HOST" \
    --port "$PORT" \
    --workers 1 \
    --proxy-headers \
    --forwarded-allow-ips '*' \
    --log-level info
