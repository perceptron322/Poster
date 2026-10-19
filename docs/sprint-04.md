## Секреты

- Реальные значения паролей и ключей хранятся только в `.env`, который в `.gitignore`.
  В репозитории лежит лишь шаблон `.env.example` с заглушками `change_me`.
- В CI секреты берутся из GitHub → Settings → Secrets and variables → Actions,
  на сервере — из `.env` с правами `600` или Docker secrets.
- Перед коммитом проверка `gitleaks` (`make secrets-scan`, pre-commit хук, CI).
- Если секрет попал в git — сначала сменить его, потом уже чистить историю.