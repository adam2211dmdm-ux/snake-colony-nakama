# Snake Colony — Nakama server for Railway (free trial, no card needed)
# Deploy: push this folder to a GitHub repo, then Railway → New Project →
# Deploy from GitHub repo. Add a PostgreSQL database, set the variable
# DATABASE_URL=${{Postgres.DATABASE_URL}}, Generate Domain (target port 7350),
# and put the domain in the game: Settings → 🌐 سيرفر الأونلاين →
# https://<your-domain>  (or <your-domain>:443)
FROM heroiclabs/nakama:3.26.0
COPY start.sh /nakama/start.sh
RUN chmod +x /nakama/start.sh
ENTRYPOINT ["/bin/sh", "/nakama/start.sh"]
