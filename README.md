# WeKnora 部署配置

本仓库保存基于 [Tencent/WeKnora](https://github.com/Tencent/WeKnora)（MIT 许可）的部署配置与运维脚本，用于在新机器上复现部署、备份数据以及迁移到云服务器。

本仓库不包含：WeKnora 源码（使用官方仓库）、`.env` 及其中的密钥、数据库与上传文档、模型文件。

## 当前部署（2026-09-27）

| 项目 | 配置 |
|---|---|
| 设备 | MacBook Pro（Apple M5 Pro，48 GB 内存） |
| 容器运行环境 | Docker Desktop 4.92.0 |
| WeKnora | v0.8.2 官方镜像，5 个容器：frontend、app、docreader、postgres、redis |
| 访问地址 | 前端 http://localhost，后端 http://localhost:8080 |
| 对话模型 | Ollama `qwen3.6:latest`（35B-A3B，23.9 GB），WeKnora 中上下文窗口设为 32768 |
| 向量模型 | Ollama `bge-m3:latest`（1024 维） |
| 重排模型 | 未配置（Ollama 不提供重排模型） |
| 知识库 | First WeKnora：文档类型，RAG 检索（向量 + 关键词） |
| 智能体 | 4 个内置智能体的对话模型为 `qwen3.6:latest`，思考模式关闭 |

## 目录结构

```
config/overrides.env.example   在官方 .env.example 基础上的改动项（不含密钥）
scripts/install.sh             新机器安装：固定版本、自动生成密钥、启动服务
scripts/backup.sh              备份数据库、上传文档与 .env
scripts/restore.sh             在新机器上恢复备份（迁移用）
docs/index.html                对外静态页（GitHub Pages），含问答挂件接入位
```

## 新机器安装

前提：已安装 Git 与 Docker（macOS 使用 Docker Desktop，Linux 使用 Docker Engine）。

```bash
git clone https://github.com/BigmaRichard/weknora.git ~/weknora-deploy && ~/weknora-deploy/scripts/install.sh
```

完成后浏览器打开 http://localhost 注册账号（系统无默认账号），再按下一节配置模型。

## 模型配置

模型记录、知识库和智能体配置保存在数据库中，恢复备份后会一并还原；全新安装时在界面中完成：

1. 添加模型（来源选 Ollama）：对话模型 `qwen3.6:latest`；向量模型 `bge-m3:latest`，维度 1024。每项用「测试」确认连通后保存。
2. 新建知识库：类型选「文档」，索引策略选「RAG 检索」，在「模型配置」中选择上述两个模型。向量模型确定后再更换需要重建索引。
3. 在「智能体」中为各内置智能体选择对话模型。知识库的模型与智能体的模型分开设置，未设置时智能体显示为未配置。
4. 「智能推理」类智能体检索知识库时需要重排模型；「快速问答」未配置重排模型时会跳过重排步骤。

### Ollama 相关说明

- macOS：Ollama 应用默认监听本机 11434 端口，容器通过 `host.docker.internal` 访问，无需额外设置。
- WeKnora 不为对话请求指定上下文长度，实际使用 Ollama 的全局设置。设为 256k 时，qwen3.6 的 KV 缓存约占 5 GB 内存；在 Ollama 设置中调至 32k 后约 0.6 GB（按比例估算）。
- Linux 服务器：容器无法访问只监听 127.0.0.1 的 Ollama，需要让 Ollama 监听 0.0.0.0（systemd 环境变量 `OLLAMA_HOST=0.0.0.0`），并用防火墙或安全组限制 11434 端口的访问来源。

## 备份

```bash
~/weknora-deploy/scripts/backup.sh
```

输出到 `backups/<时间戳>/`：

| 文件 | 内容 |
|---|---|
| `weknora.dump` | 数据库（知识库、分块、向量、模型与智能体配置） |
| `files.tar.gz` | 上传的原始文档 |
| `env` | `.env` 副本，含 SYSTEM_AES_KEY 等密钥 |
| `meta.txt` | 备份时间与镜像版本 |

`backups/` 已被 `.gitignore` 排除。备份包含密钥与业务资料，需保存在安全位置，不上传到 GitHub。建议在无人使用时备份，以免遗漏正在上传的文档。

## 迁移到云服务器

1. 本机执行 `backup.sh`，把生成的备份目录传到服务器（例如 `scp -r`）。
2. 服务器上安装 Git 与 Docker Engine 后执行：
   ```bash
   git clone https://github.com/BigmaRichard/weknora.git ~/weknora-deploy && ~/weknora-deploy/scripts/restore.sh <备份目录>
   ```
   `restore.sh` 会按 `config/overrides.env.example` 中的版本克隆 WeKnora，沿用备份中的 `.env`（保留原密钥），再恢复数据库与文档并启动服务。
3. 模型调整：
   - 向量模型：服务器上用 Ollama 运行 `bge-m3`，模型名称不变，无需重建索引。
   - 对话模型：无显卡的服务器运行 qwen3.6 速度较慢，可在界面添加 DeepSeek 等 API 模型，再把知识库与智能体的对话模型切换过去。更换对话模型不需要重建索引。
4. 访问控制：需要同事访问时，把 `FRONTEND_PORT`、`APP_PORT` 改为 `80`、`8080`，安全组只放行公司出口 IP 或通过 VPN 访问，并在 `.env` 中设置 `DISABLE_REGISTRATION=true` 改为邀请制。

迁移前后使用相同的 WeKnora 版本。升级 WeKnora 后，同步修改 `config/overrides.env.example` 中的 `WEKNORA_VERSION`。

## 对外静态页（GitHub Pages）

`docs/index.html` 是面向访客的公开页面，由 GitHub Pages 托管；问答能力由云服务器上的 WeKnora 通过「网页嵌入」挂件提供。GitHub Pages 只托管静态文件，不能运行 WeKnora 本身。

### 开启 Pages

仓库 Settings → Pages → Build and deployment：Source 选 Deploy from a branch，Branch 选 `main`、目录选 `/docs`，保存。几分钟后页面地址为 https://bigmarichard.github.io/weknora/ 。此后修改 `docs/` 下的文件并推送即自动更新。

### 接入问答挂件（服务器与 HTTPS 域名就绪后）

1. WeKnora 管理端「设置 → 网页嵌入」新建渠道，绑定快速问答类智能体。
2. 允许嵌入的域名填写页面来源 `https://bigmarichard.github.io`（填宿主页面的域名，不是 WeKnora 自己的域名）。
3. 设置限流：单 IP 每分钟上限（默认 30）与渠道每日上限（默认 10000），按预期访问量调整。
4. 复制生成的 `<script>` 代码，替换 `docs/index.html` 末尾注释中的示例，提交推送。挂件加载后页面会自动隐藏「尚未开通」提示。
5. 从 GitHub Pages 地址实际打开页面验证，不能只在管理端预览。

### 限制与注意

- WeKnora 需通过 HTTPS 域名访问，否则浏览器会拦截 https 页面发起的请求。
- GitHub Pages 没有后端，只能使用静态 token 方式，token 对访客可见。渠道只绑定公开资料的知识库；依靠域名白名单与限流控制调用量，因为每次提问会产生模型 API 费用。
- 对话模型建议使用 API（如 DeepSeek），本机 Ollama 无法提供全天在线与并发。
- GitHub Pages 限制：站点不超过 1 GB，月流量软限制 100 GB；不得用作以交易或收费软件服务为主的商业站点。
- github.io 在中国内地访问不稳定，主要面向国内访客时可把静态页放在云服务器上并使用备案域名。

## 安全要点

- `.env` 含 JWT_SECRET、SYSTEM_AES_KEY 与数据库密码，不提交到仓库（官方 `.gitignore` 与本仓库 `.gitignore` 均已排除）。SYSTEM_AES_KEY 需长期保管，丢失后已加密保存的模型 API Key 无法解密。
- 数据库与 Redis 使用官方示例密码。服务器部署时建议在首次启动前修改；已初始化后修改，需要同步更新数据库用户密码。
- WeKnora 在 2026 年 1–3 月公开过多条安全通告（含 Critical 级），服务不直接暴露于公网，并保持版本更新。

## 待办

- [ ] 配置重排模型，使「智能推理」可以检索知识库
- [ ] Ollama 上下文长度调至 32k
- [ ] 开启 GitHub Pages（Settings → Pages，main 分支 /docs 目录）
- [ ] 云服务器与 HTTPS 域名就绪后，在 `docs/index.html` 接入问答挂件
