# Venera-Nas

> 基于 [haukuen/Venera](https://github.com/haukuen/Venera) 二次开发，增加了 SMB/NAS 协议支持。

### <big><strong>⚠️ 本版本已修改包名和图标，可与原版 Venera 及其他分支版本共存安装，互不干扰。</strong></big>

## ✨ 特色功能

- **SMB 协议连接 NAS**：直接访问网络存储设备中的漫画文件
- **从 NAS 扫描导入漫画**：扫描 SMB 共享目录，自动识别漫画结构并导入
- **SMB 漫画流式阅读**：无需下载到本地，直接从 NAS 读取漫画页面
- **双模式下载**：支持下载到本地存储，或直接下载到 NAS (SMB)

## 🚀 快速开始

### 配置 SMB 服务器
1. 进入 **设置 → 网络 → SMB / NAS Servers**
2. 点击 **Add Server**，填写 NAS 信息（主机、共享名、用户名、密码）
3. 点击 **Test Connection** 验证连接

### 从 NAS 导入漫画
- 在主页点击导入旁的扫描按钮，或进入本地页面点击右上角菜单
- 选择服务器和根目录，开始扫描

### 下载方式选择
- 下载章节时，可选择 **下载到本地** 或 **下载到 NAS (SMB)**
- 可在设置中配置默认下载方式

## 📦 下载

> 前往 [Releases](https://github.com/opaiopaio/Venera-Nas/releases) 下载最新版本

## 🙏 致谢

本项目基于以下开源项目二次开发：

- **[Venera](https://github.com/venera-app/venera)**：原版漫画阅读器，提供了完整的跨平台框架
- **[haukuen/Venera](https://github.com/haukuen/Venera)**：本项目直接 Fork 自 haukuen 的维护版本，感谢他的持续维护工作

本版本（Venera-Nas）在此基础上增加了 SMB/NAS 完整支持、双模式下载等新功能。

## 📜 许可证

本项目继承原项目的开源许可证，详见 [LICENSE](LICENSE) 文件。

---

**⚠️ 注意**：本版本非官方版本，如有问题请到 [Issues](https://github.com/opaiopaio/venera-smb/issues) 反馈。