# MicGuard

**耳机负责听，Mac 负责说。**

连接蓝牙耳机后，Mac 总把麦克风也切过去，音质跟着变差？MicGuard 会自动将默认输入切回内置麦克风，手机麦克风也一样。

- 保持你选择的声音输出
- 后台运行，空闲不轮询
- 不录音、不上传数据，无第三方依赖
- 登录后自动启动

## 一行安装

打开 Mac 的「终端」，粘贴并回车：

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/LanternCX/micguard/main/install.sh)"
```

安装完成即生效，无需重启。**更新也运行同一条命令。**

需要 Apple 命令行工具；如果尚未安装，脚本会弹出安装提示，完成后再运行一次即可。已在 macOS 15.7.2 上验证。

## 怎么确认生效？

打开「系统设置 → 声音 → 输入」，应选中 Mac 内置麦克风。连接耳机后，输出仍可使用耳机。

如果会议或语音软件有独立的麦克风设置，请在软件内也选择 Mac 内置麦克风。

## 暂停使用

想使用其他麦克风？运行以下命令，停止程序并关闭自动启动：

```sh
launchctl disable "gui/$(id -u)/local.micguard"; launchctl bootout "gui/$(id -u)/local.micguard"
```

恢复时重新运行安装命令即可。

## 一行卸载

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/LanternCX/micguard/main/install.sh)" -- --uninstall
```

停止后台程序，并删除其安装文件、启动配置和日志。

## 使用说明

MicGuard 在输入切换后立即纠正，不能保证耳机完全不会短暂进入通话模式。运行期间，手动选择其他默认麦克风也会被切回；没有可用的内置麦克风时不修改输入。

程序安装在 `~/Library/Application Support/MicGuard/`，启动配置位于 `~/Library/LaunchAgents/local.micguard.plist`，无需管理员权限。

<details>
<summary>开发与排查</summary>

从本地源码安装：

```sh
git clone https://github.com/LanternCX/micguard.git
cd micguard
bash install.sh
```

查看当前设备与后台服务：

```sh
"$HOME/Library/Application Support/MicGuard/micguard" --status
launchctl print "gui/$(id -u)/local.micguard"
```

`Default input` 与 `Built-in microphone` 编号相同表示正在使用内置麦克风。日志位于 `~/Library/Application Support/MicGuard/micguard.log`。

使用 Swift、Core Audio 和 AppKit 实现，监听设备变化和唤醒事件。已验证切换到其他输入后自动恢复，以及声音输出保持不变；实际重连、睡眠唤醒和重新登录仍需验证。

</details>
