# Cloud deployment

The easiest cloud setup is a small Linux VPS running Docker.

## 1. Prepare the server

Use Ubuntu 22.04 or newer, then install Docker:

```bash
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

## 2. Upload this project

From your local machine:

```bash
scp -r "C:\Users\User\Documents\翻译机器人" user@SERVER_IP:~/telegram-translator-bot
```

Or create the files directly on the server and copy `bot.py`, `requirements.txt`, `Dockerfile`, `docker-compose.yml`, and `.env`.

## 3. Configure secrets

On the server, create `.env` in the project folder:

```env
TELEGRAM_BOT_TOKEN=replace_with_your_telegram_bot_token
OPENAI_API_KEY=replace_with_your_openai_api_key
OPENAI_MODEL=gpt-5.4-mini
TRANSLATION_CONCURRENCY=10
QUEUE_MAXSIZE=0
DROP_PENDING_UPDATES=false
LOG_LEVEL=INFO
```

Do not publish `.env` or bake it into the Docker image.

## 4. Start the bot

```bash
cd ~/telegram-translator-bot
sudo docker compose up -d --build
sudo docker compose logs -f
```

## 5. Manage the bot

```bash
sudo docker compose ps
sudo docker compose logs -f
sudo docker compose restart
sudo docker compose down
```

The container uses `restart: unless-stopped`, so it will automatically restart after crashes or server reboot.

## Telegram group note

For group usage, disable Privacy Mode in BotFather if the bot should translate every Chinese message in the group.
