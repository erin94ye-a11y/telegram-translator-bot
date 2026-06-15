# Telegram 中文到美式英文翻译机器人

这个机器人只做一件事：收到包含中文的 Telegram 文本消息后，使用 OpenAI 模型翻译成自然的美式英文并回复原消息。

## 功能

- 默认模型：`gpt-5.4-mini`
- 只处理包含中文的文本消息
- 命令和非中文消息静默忽略
- 同时最多处理 `10` 条 OpenAI 翻译请求
- 超过并发上限的消息自动进入后台队列，不发送排队提示
- 支持多人和群组使用

## 配置

复制 `.env.example` 为 `.env`，然后填写：

```env
TELEGRAM_BOT_TOKEN=你的 Telegram Bot Token
OPENAI_API_KEY=你的 OpenAI API Key
OPENAI_MODEL=gpt-5.4-mini
TRANSLATION_CONCURRENCY=10
QUEUE_MAXSIZE=0
```

如果要在群组中翻译所有中文消息，需要在 BotFather 里关闭机器人的 Privacy Mode，否则 Telegram 只会把命令、提及或回复机器人的消息发给机器人。

## 安装

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

## 启动

```powershell
python bot.py
```

Windows 桌面上也可以直接双击：

- `start_local_visible.cmd`：可见窗口启动，最适合第一次测试
- `start_bot_hidden.vbs`：隐藏窗口后台启动
- `restart_bot_hidden.cmd`：重启隐藏后台机器人
- `stop_bot.cmd`：停止后台机器人
- `view_bot_log.cmd`：查看运行日志
- `test_autostart.cmd`：安装并测试 Windows 登录自启
- `install_autostart.cmd`：安装为 Windows 登录后自动启动
- `uninstall_autostart.cmd`：取消 Windows 登录自启

如果不想在 Windows 本地运行，有两种云端方式：

- Cloudflare Workers：看 `cloudflare-worker/README.md`
- 云服务器 Docker：看 `CLOUD_DEPLOY.md`

启动后，把机器人拉进群组或私聊发送中文即可。超过 10 条同时翻译的消息会静默排队。
