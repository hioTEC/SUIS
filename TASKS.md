# SUI Solo - 开发任务清单

## 🔴 高优先级

### 1. 修复 Master-Node 状态互通
- [x] 1.1 检查 node/agent.py 容器状态查询逻辑
- [x] 1.2 修复容器名称匹配问题 (sui-caddy -> sui-gateway)
- [x] 1.3 确保 Docker socket 权限正确 (移除 cap_drop: ALL)
- [ ] 1.4 测试 /services API 返回正确状态

### 2. 实现聚合订阅生成
- [ ] 2.1 Master 添加订阅生成 API `/api/subscribe`
- [ ] 2.2 支持多种格式 (Base64, Clash, Sing-box)
- [ ] 2.3 聚合所有在线节点的代理配置
- [ ] 2.4 面板添加订阅链接显示和复制按钮

### 3. Sing-box 配置下发
- [ ] 3.1 Master 面板添加配置编辑器
- [ ] 3.2 支持预设模板 (VLESS/VMess/Hysteria2/Reality)
- [ ] 3.3 Node Agent 接收配置并重启 Sing-box
- [ ] 3.4 配置验证和错误处理

## 🟡 中优先级

### 4. 快速连接功能
- [ ] 4.1 一键生成客户端配置
- [ ] 4.2 生成二维码供手机扫描
- [ ] 4.3 支持多种客户端格式 (v2rayN, Clash, Shadowrocket)
- [ ] 4.4 面板添加"快速连接"按钮

### 5. Node /stats API 增强
- [ ] 5.1 返回 CPU 使用率
- [ ] 5.2 返回内存使用情况
- [ ] 5.3 返回在线时长
- [ ] 5.4 返回流量统计

### 6. 配置模板系统
- [ ] 6.1 预设 VLESS + Reality 模板
- [ ] 6.2 预设 VMess + WS 模板
- [ ] 6.3 预设 Hysteria2 模板
- [ ] 6.4 模板参数化 (UUID/端口/域名自动填充)

## 🟢 低优先级

### 7. README 完善
- [ ] 7.1 添加 Mermaid 架构图
- [ ] 7.2 添加 Badges (Docker/Python/License)
- [ ] 7.3 完善安全说明
- [ ] 7.4 添加 FAQ

### 8. 代码质量提升
- [ ] 8.1 将 subprocess 改为 python-on-whales/docker SDK
- [ ] 8.2 添加单元测试
- [ ] 8.3 添加 CI/CD 配置

---

## 📝 进度记录

| 日期 | 版本 | 完成内容 |
|------|------|----------|
| 2025-12-06 | 1.9.10 | 基础框架完成，修复安装脚本 |
| 2025-12-06 | 1.9.11 | 修复 Master-Node 状态互通 |
