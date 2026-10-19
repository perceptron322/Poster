#!/bin/sh
# Создаёт или дополняет .env по шаблону: недостающие переменные добавляются,
# заглушки change_me* заменяются отдельным случайным значением для каждой.
# Уже заданные значения не трогаются.
#
# Использование: sh scripts/env-init.sh [шаблон] [файл]
set -eu

example=${1:-.env.example}
target=${2:-.env}

umask 077
touch "$target"
chmod 600 "$target"
# Файл без перевода строки в конце склеил бы последнюю строку с новой.
if [ -s "$target" ] && [ -n "$(tail -c1 "$target")" ]; then
    echo >> "$target"
fi

added=0
while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in '' | '#'*) continue ;; esac
    key=${line%%=*}
    grep -q "^$key=" "$target" && continue
    value=${line#*=}
    case "$value" in change_me*) value=$(openssl rand -hex 16) ;; esac
    printf '%s=%s\n' "$key" "$value" >> "$target"
    added=$((added + 1))
done < "$example"

echo "$target: добавлено переменных: $added"
