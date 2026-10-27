# Agent 状态右岛

布局：左岛继续显示番茄钟，原主岛保持原来的位置，右岛汇总本机 Agent 会话。
点击右岛展开主岛的 Agents 列表；没有活动时也可从主岛的 sparkles 标签进入。

## 显示规则

- 黄色 `! N`：N 个会话待处理，优先于其他状态。
- 红色 `! N`：N 个会话报告执行失败。
- 蓝色图标与数字：正在运行的会话数量。
- 有待处理或失败会话时，顶部蓝点表示还有其他会话运行中。
- 完成短暂显示绿色勾 8 秒，再恢复运行数；待处理和失败仍有更高优先级。
- 连续 5 分钟没有新事件的运行/等待会话降为“状态未知”，不猜测成功或失败。
- 超过 1 小时的状态不占据小岛；最近 24 小时的会话仍可在列表中查看。
- 主岛展开、隐藏或宽度不足以容纳卫星岛时，右岛暂时隐藏。

## 已支持的来源

### Codex（桌面与 CLI 的本地会话）

只读扫描 `.codex/sessions` JSONL，按会话 ID 去重，排除明确标识的子 Agent，
从 `session_index.jsonl` 读取会话名称。支持开始、完成、中断，以及明确的同步
`request_user_input` 请求/响应。点击列表行使用 `codex://threads/<id>` 跳回会话。

这是对本机已核验日志格式的适配，**不是对 Codex 桌面进程的 app-server 连接**。
独立启动另一个 app-server 不能可靠读取现有桌面进程内存中的审批状态，因而没有这样做。
日志没有明确事件的审批、异步提问、云端会话以及其他电脑的会话不保证识别。
仅将成功调用工具或进程存在视为“已完成”也是不正确的，本实现不这样推断。

每 2 秒增量读取，最多读取 2 MiB 新内容；每 15 秒发现近期文件，最多监控 200 个。
首次读取过长文件从尾部开始，若缺失必要事件则显示未知；不会载入完整聊天到内存。

### Claude Code（本地 hooks）

在安装了 Python 3 的 Mac 上，在仓库目录运行：

```sh
python3 scripts/agent-status/install_claude_hooks.py
```

安装器保留原有配置和 hooks，修改前备份 `.claude/settings.json`，可重复运行。
安装后请重新打开 Claude Code 会话，以保证新的 hooks 被加载。

通过 UserPromptSubmit、PreToolUse、PermissionRequest、PostToolUse、Stop、
StopFailure、SessionEnd 和 permission_prompt 通知上报状态。
`PermissionRequest` 之后，要等后续工具事件才能清除提示，因此批准后执行耗时工具期间，
状态可能短暂仍显示“已请求权限”。工具自身失败不等于整个 Agent 任务失败。

Hook 只写会话 ID、项目目录名、通用状态与时间，不保存提示词、命令、输出或凭据；
输出为空，不替用户批准或拒绝任何操作。状态文件在 `.claude/boring-notch-events/`。
列表行复制 `claude --resume '<session-id>'`，不自动执行终端命令。

### Qoder（本地 hooks）

在仓库目录运行：

```sh
python3 scripts/agent-status/install_qoder_hooks.py
```

安装器保留 `.qoder/settings.json` 中的原有配置和 hooks，修改前备份，可重复运行。
安装后需要重启 Qoder IDE，新的 hooks 才会加载。状态事件与 Claude 使用相同的最小元数据边界，
保存在 `.qoder/boring-notch-events/`，不会保存提示词、工具输入、输出或凭据。

## 文件权限与关闭

默认读取用户目录下 `.codex` / `.claude` / `.qoder`；若应用受沙盒限制或使用自定义目录，
在 Agents 面板点击来源名称，选择对应目录，应用保存安全作用域书签。
在设置的 Agents 页勾选需要加入岛的来源；关闭面板顶部的 Agent 状态开关即停止扫描并隐藏右岛。

卸载 Claude 或 Qoder 接入：从对应 `settings.json` 的 hooks 中移除 command 或 args 含
`boring_notch_status.py` 的条目。只删除这些条目，保留其他 hooks；然后可删除对应目录下
`hooks/boring_notch_status.py` 和 `boring-notch-events`。

## 验证

```sh
swiftc -swift-version 5 boringNotch/models/AgentSession.swift \
  boringNotch/managers/AgentStatusReader.swift tests/agent-status/main.swift \
  -o /tmp/agent-status-tests
/tmp/agent-status-tests
python3 tests/agent-status/test_hooks.py
```

Fork Build 工作流会先运行这些测试，再编译应用。

官方接口参考：
- https://learn.chatgpt.com/docs/app-server （运行时状态与通知；此版未连接现有桌面运行时）
- https://code.claude.com/docs/en/hooks （Claude 生命周期 hook 输入和配置）
- https://docs.qoder.com/extensions/hooks （Qoder Desktop 生命周期 hook 输入和配置）
