#!/bin/bash
set -e

USER_ID="${HOST_UID:-1000}"
GROUP_ID="${HOST_GID:-1000}"
UMASK="${UMASK:-0000}"

EXISTING_USER=$(getent passwd "$USER_ID" | cut -d: -f1 || true)
if [ -n "$EXISTING_USER" ] && [ "$EXISTING_USER" != "builder" ]; then
    userdel -r "$EXISTING_USER" 2>/dev/null || true
fi
EXISTING_GROUP=$(getent group "$GROUP_ID" | cut -d: -f1 || true)
if [ -n "$EXISTING_GROUP" ] && [ "$EXISTING_GROUP" != "builder" ]; then
    groupmod -n builder "$EXISTING_GROUP"
fi
if ! getent group builder >/dev/null 2>&1; then
    groupadd -g "$GROUP_ID" builder
fi
if ! getent passwd builder >/dev/null 2>&1; then
    useradd -l -u "$USER_ID" -g "$GROUP_ID" -m -s /bin/bash builder
fi

grep -q "builder ALL=(ALL) NOPASSWD:ALL" /etc/sudoers 2>/dev/null || \
    echo "builder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

mkdir -p /home/builder
chown builder:builder /home/builder

umask "$UMASK"
exec gosu builder "$@"
