// 国际化字典（单一来源）。
// key = 中文原文，value = { zh, en }。对应 iOS 的 Localizable.xcstrings。
// 用 t("中文原文", ...args) 取译文；占位符用 {0}/{1}（数字按顺序替换）。

export type Lang = "zh" | "en";

type Entry = { zh: string; en: string };

const DICT: Record<string, Entry> = {
  // 通用
  "取消": { zh: "取消", en: "Cancel" },
  "完成": { zh: "完成", en: "Done" },
  "删除": { zh: "删除", en: "Delete" },
  "清空": { zh: "清空", en: "Clear" },
  "好": { zh: "好", en: "OK" },
  "返回": { zh: "返回", en: "Back" },
  "保存": { zh: "保存", en: "Save" },
  "分享": { zh: "分享", en: "Share" },
  "重拍": { zh: "重拍", en: "Retake" },
  "设置": { zh: "设置", en: "Settings" },

  // 顶栏 / Tab
  "拍 立 贴": { zh: "拍 立 贴", en: "Snap Sticker" },
  "拍立贴": { zh: "拍立贴", en: "Snap Sticker" },
  "日历": { zh: "日历", en: "Calendar" },
  "拍照": { zh: "拍照", en: "Camera" },

  // 快门提示
  "冲印中": { zh: "冲印中", en: "Developing" },
  "再拍一张": { zh: "再拍一张", en: "Shoot Again" },
  "按下快门": { zh: "按下快门", en: "Press the Shutter" },
  "启动相机…": { zh: "启动相机…", en: "Starting Camera…" },
  "摇一摇加速显影": { zh: "摇一摇加速显影", en: "Shake to develop faster" },

  // 原图 / 贴图
  "原图": { zh: "原图", en: "Original" },
  "贴图": { zh: "贴图", en: "Sticker" },
  "原始照片": { zh: "原始照片", en: "Original Photo" },

  // 摄像头
  "需要摄像头权限": { zh: "需要摄像头权限", en: "Camera Access Needed" },
  "允许使用摄像头": { zh: "允许使用摄像头", en: "Allow Camera" },
  "前往系统设置": { zh: "前往系统设置", en: "Open Settings" },
  "正在请求…": { zh: "正在请求…", en: "Requesting…" },
  "摄像头权限被拒绝。请在浏览器地址栏或系统设置里允许访问摄像头，然后重试。": {
    zh: "摄像头权限被拒绝。请在浏览器地址栏或系统设置里允许访问摄像头，然后重试。",
    en: "Camera access denied. Allow camera access in the address bar or Settings, then try again.",
  },
  "没有找到可用的摄像头设备。": { zh: "没有找到可用的摄像头设备。", en: "No camera device available." },
  "摄像头正被其他应用占用，请关闭后重试。": {
    zh: "摄像头正被其他应用占用，请关闭后重试。",
    en: "The camera is in use by another app. Close it and try again.",
  },
  "当前页面无法调用摄像头。请用 HTTPS 或 localhost 打开本应用。": {
    zh: "当前页面无法调用摄像头。请用 HTTPS 或 localhost 打开本应用。",
    en: "This page can't access the camera. Open the app over HTTPS or localhost.",
  },
  "无法访问摄像头，请检查浏览器权限设置后重试。": {
    zh: "无法访问摄像头，请检查浏览器权限设置后重试。",
    en: "Can't access the camera. Check browser permissions and try again.",
  },

  // 拍照流程错误 / toast
  "没抓到画面，请重试": { zh: "没抓到画面，请重试", en: "Didn't catch a frame. Try again." },
  "贴纸生成失败，已保留原图": { zh: "贴纸生成失败，已保留原图", en: "Sticker generation failed; kept the original." },
  "没识别到主体，已保留原图": { zh: "没识别到主体，已保留原图", en: "No subject detected; kept the original." },
  "已保存到相册": { zh: "已保存到相册", en: "Saved" },
  "生成分享图失败，请重试": { zh: "生成分享图失败，请重试", en: "Couldn't create the share image. Try again." },

  // 相纸
  "相纸": { zh: "相纸", en: "Paper" },
  "选择相纸": { zh: "选择相纸", en: "Choose Paper" },
  "经典奶油白": { zh: "经典奶油白", en: "Classic Cream" },
  "牛皮手帐": { zh: "牛皮手帐", en: "Kraft Journal" },
  "克莱因蓝": { zh: "克莱因蓝", en: "Klein Blue" },
  "琥珀暖光": { zh: "琥珀暖光", en: "Amber Glow" },
  "深海渐变": { zh: "深海渐变", en: "Deep Sea" },
  "炭灰胶片": { zh: "炭灰胶片", en: "Charcoal Film" },
  "手帐胶带": { zh: "手帐胶带", en: "Washi Tape" },

  // 历史
  "历史记录": { zh: "历史记录", en: "History" },
  "共 {0} 张": { zh: "共 {0} 张", en: "{0} in total" },
  "显示贴纸": { zh: "显示贴纸", en: "Visible Stickers" },
  "贴纸快照": { zh: "贴纸快照", en: "Sticker Snapshot" },
  "清空所有记录": { zh: "清空所有记录", en: "Clear All History" },
  "还没有贴纸": { zh: "还没有贴纸", en: "No stickers yet" },
  "按下快门拍一张吧": { zh: "按下快门拍一张吧", en: "Press the shutter to take one" },
  "删除这张贴纸？": { zh: "删除这张贴纸？", en: "Delete this sticker?" },
  "删除后会从历史记录和散落贴纸中移除。": {
    zh: "删除后会从历史记录和散落贴纸中移除。",
    en: "It will be removed from history and the sandbox.",
  },
  "清空所有记录？": { zh: "清空所有记录？", en: "Clear all history?" },
  "这个操作会删除全部历史贴纸，无法撤销。": {
    zh: "这个操作会删除全部历史贴纸，无法撤销。",
    en: "This deletes all sticker history and can't be undone.",
  },
  "输入「我确认」继续": { zh: "输入「我确认」继续", en: 'Type "I confirm" to continue' },
  "我确认": { zh: "我确认", en: "I confirm" },
  "隐藏这张贴纸": { zh: "隐藏这张贴纸", en: "Hide this sticker" },
  "展示这张贴纸": { zh: "展示这张贴纸", en: "Show this sticker" },

  // 日历
  "月": { zh: "月", en: "Month" },
  "周": { zh: "周", en: "Week" },
  "日": { zh: "日", en: "Day" },
  "今天": { zh: "今天", en: "Today" },
  "昨天": { zh: "昨天", en: "Yesterday" },
  "回到今天": { zh: "回到今天", en: "Back to Today" },
  "这一天还没有贴纸": { zh: "这一天还没有贴纸", en: "No stickers on this day" },
  "倾斜手机，贴纸会到处跑": { zh: "倾斜手机，贴纸会到处跑", en: "Tilt your phone — the stickers roll around" },

  // 用户中心
  "总贴纸": { zh: "总贴纸", en: "Total" },
  "本月": { zh: "本月", en: "This Month" },
  "活跃天数": { zh: "活跃天数", en: "Active Days" },
  "主题外观": { zh: "主题外观", en: "Appearance" },
  "界面语言": { zh: "界面语言", en: "Language" },
  "跟随系统": { zh: "跟随系统", en: "System" },
  "白天": { zh: "白天", en: "Light" },
  "黑夜": { zh: "黑夜", en: "Dark" },
  "中文": { zh: "中文", en: "中文" },
  "English": { zh: "English", en: "English" },
  "回看与管理全部贴纸": { zh: "回看与管理全部贴纸", en: "Browse and manage all stickers" },
  "贴纸物理": { zh: "贴纸物理", en: "Sticker Physics" },
  "移动速度与倾斜灵敏度": { zh: "移动速度与倾斜灵敏度", en: "Speed and tilt sensitivity" },
  "关于拍立贴": { zh: "关于拍立贴", en: "About SnapStick" },
  "对准、按下快门，AI 把此刻冲印成贴纸": {
    zh: "对准、按下快门，AI 把此刻冲印成贴纸",
    en: "Aim, press the shutter — AI develops the moment into a sticker",
  },

  // 设置（贴纸物理）
  "贴纸设置": { zh: "贴纸设置", en: "Sticker Settings" },
  "移动速度": { zh: "移动速度", en: "Speed" },
  "倾斜灵敏度": { zh: "倾斜灵敏度", en: "Tilt Sensitivity" },
  "重置为默认": { zh: "重置为默认", en: "Reset to Default" },

  // 方向感应
  "启用方向感应": { zh: "启用方向感应", en: "Enable Motion" },
  "允许后，贴纸会跟随手机倾斜滑动。": {
    zh: "允许后，贴纸会跟随手机倾斜滑动。",
    en: "Once allowed, stickers slide as you tilt your phone.",
  },
  "启用": { zh: "启用", en: "Enable" },
  "稍后": { zh: "稍后", en: "Later" },
  "启用方向传感器": { zh: "启用方向传感器", en: "Enable Motion Sensor" },
};

/** 把 {0} {1} 占位符替换为参数（数字会原样 toString）。 */
function fill(template: string, args: (string | number)[]): string {
  return template.replace(/\{(\d+)\}/g, (_, i) => {
    const v = args[Number(i)];
    return v === undefined ? "" : String(v);
  });
}

/** 取译文。未登记的 key 原样返回（容错）。 */
export function translate(key: string, lang: Lang, ...args: (string | number)[]): string {
  const entry = DICT[key];
  const raw = entry ? entry[lang] : key;
  return args.length ? fill(raw, args) : raw;
}
