# Sparkle 更新发布

- Sparkle 2.10.1，固定官方下载 SHA-256；`vendor/` 不提交。
- 应用：DockHush；版本：0.3.0；原 Bundle ID 保持不变。
- 更新源：https://github.com/syczk301/DockHush/releases/download/sparkle/appcast.xml
- 签名钥匙串账户：`syczk301.DockHush`。私钥只保存在登录钥匙串，切勿提交或上传。
- 应用要求更新 ZIP 和 appcast 均通过 Ed25519 签名验证。
- 自动检查已启用；自动下载安装默认关闭，由用户在 Sparkle 中选择。

## 构建

运行本项目原有构建脚本。脚本先下载并验证 Sparkle，再嵌入 Framework、设置 rpath 和公钥，最后签名主应用。`ditto` 保留 Framework 的软链接和可执行权限。

## 发布

1. 递增 `CFBundleVersion` 和显示版本（保留原 Bundle ID、更新公钥）。
2. 构建后运行：

```sh
python3 tools/sparkle/release.py 'build/DockHush.app' /path/to/release-staging
```

3. 允许 `generate_appcast` 访问本应用签名钥匙串项。
4. 将签名 ZIP 上传到 `syczk301/DockHush` 的固定 `sparkle` Release，保留旧版本 ZIP。
5. **最后**上传 `appcast.xml`，覆盖旧 feed。签名后不要手改 XML 或归档。
6. 匿名下载 feed/ZIP，校验签名，再用旧测试副本验证检查更新、安装和重启。

首次接入必须安装一次带 Sparkle 的新版。旧版本没有更新器，无法自行迁移。
当前构建仍使用本地 ad-hoc 应用签名，更新签名与 Apple Developer ID/公证是不同机制，不能把前者称为已公证。正式 Developer ID 分发应传入正确签名身份并完成公证，保留既有签名身份和用户权限。

`config.json` 中的 GitHub 地址只有在固定 Release 及签名文件实际发布后才可用。不能把本地构建成功当作线上更新成功。
