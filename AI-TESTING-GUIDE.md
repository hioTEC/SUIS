# AI-CLI 测试推荐方案

## 推荐的 AI-CLI 工具

### 方案 1: OpenAI CLI（推荐用于生产环境）

**优点**:
- 响应质量高
- 理解复杂问题能力强
- 适合诊断和分析

**安装**:
```bash
npm install -g @openai/cli
export OPENAI_API_KEY="your-api-key"
```

**使用**:
```bash
# 设置别名
alias ai='openai'

# 测试
ai "Hello, test"
```

### 方案 2: Anthropic Claude CLI（推荐用于技术分析）

**优点**:
- 技术分析能力强
- 代码理解准确
- 适合配置文件分析

**安装**:
```bash
pip install anthropic-cli
export ANTHROPIC_API_KEY="your-api-key"
```

**使用**:
```bash
# 设置别名
alias ai='claude'

# 测试
ai "Analyze this configuration"
```

### 方案 3: Ollama（推荐用于本地测试）

**优点**:
- 完全本地运行
- 无需 API 密钥
- 免费使用
- 数据隐私

**安装**:
```bash
# 安装 Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# 下载模型
ollama pull llama2        # 7B 模型，快速
ollama pull codellama     # 代码专用
ollama pull mistral       # 平衡性能

# 设置别名
alias ai='ollama run llama2'
```

**使用**:
```bash
# 测试
ai "Analyze this log file"
```

## 推荐的测试流程

### 第一步：部署前检查

```bash
# 1. 检查服务器环境
ai "我要在 Ubuntu 22.04 上部署 Docker 应用，需要检查哪些系统要求？"

# 2. 验证域名配置
ai "我的域名是 node.example.com，如何验证 DNS 是否正确配置？"

# 3. 检查端口
ss -tlnp | grep -E ':(80|443)' > ports.txt
ai "分析这些端口占用情况，是否有冲突：" < ports.txt
```

### 第二步：部署

```bash
# 运行安装脚本
sudo ./install.sh

# 启动服务
cd /opt/sui-proxy/gateway && sudo docker compose up -d
sleep 10
cd /opt/sui-proxy/node && sudo docker compose up -d
```

### 第三步：自动化测试

```bash
# 运行基础测试
sudo ./test-deployment.sh

# 使用 AI 辅助测试（推荐）
sudo ./ai-test-helper.sh all
```

### 第四步：深度分析

```bash
# 1. 分析部署状态
sudo ./ai-test-helper.sh deploy

# 2. 验证配置文件
sudo ./ai-test-helper.sh config

# 3. 检查错误
sudo ./ai-test-helper.sh error

# 4. 性能评估
sudo ./ai-test-helper.sh perf

# 5. 安全检查
sudo ./ai-test-helper.sh security
```

## 具体测试场景

### 场景 1: 验证 Fallback 机制

```bash
# 收集信息
cat > /tmp/fallback-test.txt << EOF
Sing-box 配置:
$(jq '.inbounds[] | select(.type == "vless")' /opt/sui-proxy/node/config/singbox/config.json)

容器网络:
$(docker network inspect sui-master-net --format '{{range .Containers}}{{.Name}} {{end}}')

连接测试:
$(docker exec sui-singbox ping -c 3 sui-gateway 2>&1)

HTTPS 测试:
$(curl -k -v https://master.example.com/ 2>&1 | head -20)
EOF

# AI 分析
ai "分析这个 Sing-box fallback 配置是否正确，以及 HTTPS 流量是否正确转发到 Caddy：" < /tmp/fallback-test.txt
```

### 场景 2: 诊断启动失败

```bash
# 收集日志
docker logs sui-singbox > /tmp/singbox-error.log 2>&1

# AI 诊断
ai "Sing-box 容器启动失败，分析以下日志并提供解决方案：" < /tmp/singbox-error.log
```

### 场景 3: 性能优化

```bash
# 收集性能数据
cat > /tmp/performance.txt << EOF
容器资源:
$(docker stats --no-stream sui-gateway sui-singbox)

连接数:
TCP 80: $(ss -tn | grep :80 | wc -l)
TCP 443: $(ss -tn | grep :443 | wc -l)

系统负载:
$(uptime)
$(free -h)
EOF

# AI 分析
ai "分析这些性能数据，提供优化建议：" < /tmp/performance.txt
```

### 场景 4: 生成客户端配置

```bash
# 读取服务器配置
source /opt/sui-proxy/config/config.env

# 请求 AI 生成
ai "生成 VLESS 客户端配置：
服务器: ${NODE_DOMAIN}
端口: 443
UUID: ${VLESS_UUID}
Flow: xtls-rprx-vision
TLS: 启用

请提供：
1. V2Ray JSON 配置
2. Clash YAML 配置
3. Sing-box 客户端配置
4. 连接 URI"
```

### 场景 5: 安全审计

```bash
# 收集安全信息
cat > /tmp/security-audit.txt << EOF
配置文件权限:
$(ls -la /opt/sui-proxy/config/)

Sing-box 配置:
$(jq '{tls: .inbounds[0].tls, fallback: .inbounds[0].fallback}' /opt/sui-proxy/node/config/singbox/config.json)

开放端口:
$(ss -tlnp)

防火墙状态:
$(ufw status 2>/dev/null || iptables -L -n)

Docker 安全:
$(docker inspect sui-singbox --format '{{.Config.User}}')
$(docker inspect sui-singbox --format '{{.HostConfig.Privileged}}')
EOF

# AI 审计
ai "进行安全审计，指出潜在风险和加固建议：" < /tmp/security-audit.txt
```

## AI-CLI 最佳实践

### 1. 提供上下文

❌ 不好的提问:
```bash
ai "为什么不工作？"
```

✅ 好的提问:
```bash
ai "我的 Sing-box 容器无法启动，这是错误日志：
$(docker logs sui-singbox 2>&1 | tail -30)

配置文件：
$(jq . /opt/sui-proxy/node/config/singbox/config.json)

请分析问题并提供解决方案。"
```

### 2. 分步骤提问

```bash
# 第一步：理解问题
ai "Sing-box fallback 机制的工作原理是什么？"

# 第二步：验证配置
ai "检查这个配置是否正确：" < config.json

# 第三步：诊断问题
ai "根据这些日志，fallback 为什么不工作：" < logs.txt

# 第四步：获取解决方案
ai "如何修复 fallback 配置问题？"
```

### 3. 使用结构化输出

```bash
ai "分析部署状态，按以下格式输出：
1. 问题列表
2. 严重程度（高/中/低）
3. 解决方案
4. 验证步骤

部署信息：
$(docker ps -a)
$(docker logs sui-gateway --tail 20)"
```

### 4. 保存 AI 建议

```bash
# 保存分析结果
./ai-test-helper.sh deploy > /tmp/ai-analysis.txt

# 后续参考
cat /tmp/ai-analysis.txt
```

## 集成到 CI/CD

### GitHub Actions 示例

```yaml
name: Deploy and Test

on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Deploy to server
        run: |
          scp -r . user@server:/tmp/sui-proxy
          ssh user@server 'cd /tmp/sui-proxy && sudo ./install.sh'
      
      - name: Run tests
        run: |
          ssh user@server 'cd /tmp/sui-proxy && sudo ./test-deployment.sh'
      
      - name: AI Analysis
        env:
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
        run: |
          ssh user@server 'cd /tmp/sui-proxy && sudo ./ai-test-helper.sh all'
```

## 故障排查流程图

```
部署失败？
    ↓
运行 test-deployment.sh
    ↓
有失败的测试？
    ↓ 是
运行 ai-test-helper.sh error
    ↓
AI 提供解决方案
    ↓
应用修复
    ↓
重新测试
    ↓
成功？
    ↓ 是
运行 ai-test-helper.sh all
    ↓
全面验证
    ↓
部署完成！
```

## 常用 AI 提示词模板

### 配置分析
```
分析以下 [Sing-box/Caddy] 配置文件：
1. 检查语法错误
2. 验证端口配置
3. 检查安全设置
4. 提供优化建议

配置内容：
[粘贴配置]
```

### 日志诊断
```
分析以下 Docker 容器日志：
1. 识别错误和警告
2. 找出根本原因
3. 提供解决步骤
4. 建议预防措施

日志内容：
[粘贴日志]
```

### 性能优化
```
基于以下性能数据：
1. 评估当前性能
2. 识别瓶颈
3. 提供优化建议
4. 估算改进效果

性能数据：
[粘贴数据]
```

### 安全审计
```
进行安全审计：
1. 识别安全风险
2. 评估风险等级
3. 提供加固方案
4. 给出实施步骤

系统信息：
[粘贴信息]
```

## 总结

使用 AI-CLI 进行测试的优势：

1. **智能分析**: AI 可以理解复杂的日志和配置
2. **快速诊断**: 自动识别问题和提供解决方案
3. **学习助手**: 解释技术概念和最佳实践
4. **文档生成**: 自动生成配置和文档
5. **持续改进**: 基于反馈优化部署流程

推荐工作流：
1. 使用 `test-deployment.sh` 进行基础测试
2. 使用 `ai-test-helper.sh` 进行深度分析
3. 根据 AI 建议进行优化
4. 重新测试验证
5. 记录和分享经验

祝测试顺利！🚀
