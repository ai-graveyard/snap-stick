"use client";

import { useState } from "react";
import Link from "next/link";

// 联系方式（中英文共用）：走 GitHub Issues，不暴露个人邮箱
const CONTACT_URL = "https://github.com/ai-graveyard/pai-li-tie/issues";
const CONTACT_LABEL_TEXT = "GitHub Issues";

type Lang = "zh" | "en";

// 隐私政策正文：中英双语，结构一致，便于维护
const COPY: Record<
  Lang,
  {
    langLabel: string; // 语言切换按钮上显示的「切到另一种语言」文案
    title: string;
    subtitle: string;
    updated: string;
    intro: string;
    sections: { heading: string; paras?: string[]; list?: string[] }[];
    contactLabel: string;
    back: string;
  }
> = {
  zh: {
    langLabel: "EN",
    title: "隐私政策",
    subtitle: "拍立贴 · SnapStick",
    updated: "最近更新：2026 年 6 月 4 日",
    intro:
      "拍立贴（SnapStick，以下简称「本应用」）是一款模拟拍立得相机的应用：你用摄像头「拍」一张照片，本应用会把它冲印成一张专属卡通贴纸。我们非常重视你的隐私，本政策说明本应用会收集哪些信息、如何使用，以及你拥有哪些权利。",
    sections: [
      {
        heading: "1. 我们收集的信息",
        paras: [
          "本应用**不要求注册或登录**，不会收集你的姓名、手机号、邮箱或其他可直接识别身份的个人信息。本应用涉及的数据包括：",
        ],
        list: [
          "**摄像头画面与照片**：当你授权使用摄像头并按下快门时，本应用会捕获一张照片，用于生成贴纸。",
          "**生成的贴纸**：在你设备本地处理生成的卡通贴纸图片。",
          "**历史作品**：你拍摄并生成的贴纸会保存在你设备本地，方便你回看与收藏。",
        ],
      },
      {
        heading: "2. 信息如何存储",
        list: [
          "**本地优先**：你的照片与生成的贴纸默认**仅保存在你自己的设备上**（应用本地存储 / 浏览器 IndexedDB），不会上传到我们的服务器长期保存。",
          "**随时删除**：你可以在应用内一键清空历史记录，或删除单张作品。卸载应用或清除应用数据后，本地数据也会一并移除。",
        ],
      },
      {
        heading: "3. 信息如何使用",
        paras: [
          "把照片转换成卡通贴纸所需的全部图像处理，都**在你的设备本地完成**，使用系统提供的图像处理能力：",
        ],
        list: [
          "你的照片**全程不会离开你的设备**，不会上传到我们或任何第三方的服务器。",
          "本应用**不接入任何第三方 AI 或云端图像生成服务**。",
          "我们不会将你的照片用于广告、画像分析或出售给任何第三方。",
        ],
      },
      {
        heading: "4. 我们不会做的事",
        list: [
          "不会在未经你授权的情况下访问摄像头。",
          "不会收集你的位置信息、通讯录或设备唯一标识用于追踪。",
          "不会出售、出租你的照片或个人数据。",
          "不会投放基于个人数据的定向广告。",
        ],
      },
      {
        heading: "5. 权限说明",
        paras: [
          "本应用会请求**摄像头权限**，仅用于拍摄照片以生成贴纸。你可以随时在系统设置中关闭该权限；关闭后将无法使用拍摄功能，但不影响查看已保存的历史作品。",
        ],
      },
      {
        heading: "6. 儿童隐私",
        paras: [
          "本应用不面向 13 周岁以下儿童。我们不会有意收集儿童的个人信息。如果你认为儿童在未经监护人同意的情况下向我们提供了信息，请联系我们删除。",
        ],
      },
      {
        heading: "7. 你的权利",
        paras: [
          "由于数据主要保存在你的设备本地，你可以随时通过应用内功能查看、回看与删除你的作品，从而完全掌控自己的数据。",
        ],
      },
      {
        heading: "8. 政策更新",
        paras: [
          "我们可能会不时更新本隐私政策。更新后会在本页面更新「最近更新」日期。建议你定期查阅本页面以了解最新内容。",
        ],
      },
      {
        heading: "9. 联系我们",
        paras: ["如果你对本隐私政策有任何疑问或诉求，可以通过以下方式联系我们："],
      },
    ],
    contactLabel: "反馈：",
    back: "← 返回拍立贴",
  },
  en: {
    langLabel: "中文",
    title: "Privacy Policy",
    subtitle: "拍立贴 · SnapStick",
    updated: "Last updated: June 4, 2026",
    intro:
      'SnapStick (拍立贴, the "App") is an app that mimics an instant camera: you "take" a photo with your camera, and the App develops it into a unique cartoon sticker. We take your privacy seriously. This policy explains what information the App handles, how it is used, and the rights you have.',
    sections: [
      {
        heading: "1. Information We Collect",
        paras: [
          "The App requires **no registration or login** and does not collect your name, phone number, email, or any other directly identifying personal information. The data involved includes:",
        ],
        list: [
          "**Camera feed and photos**: When you grant camera access and press the shutter, the App captures a photo to generate a sticker.",
          "**Generated stickers**: The cartoon sticker image processed locally on your device.",
          "**History**: The stickers you create are saved locally on your device so you can revisit and collect them.",
        ],
      },
      {
        heading: "2. How Information Is Stored",
        list: [
          "**Local-first**: Your photos and generated stickers are by default **stored only on your own device** (app local storage / browser IndexedDB) and are not uploaded to our servers for long-term storage.",
          "**Delete anytime**: You can clear your entire history or delete individual works within the App. Uninstalling the App or clearing its data also removes the local data.",
        ],
      },
      {
        heading: "3. How Information Is Used",
        paras: [
          "All image processing needed to turn your photo into a cartoon sticker is performed **locally on your device**, using the system's built-in image processing capabilities:",
        ],
        list: [
          "Your photos **never leave your device** and are not uploaded to our servers or any third party's servers.",
          "The App **does not connect to any third-party AI or cloud image generation service**.",
          "We do not use your photos for advertising, profiling, or sell them to any third party.",
        ],
      },
      {
        heading: "4. What We Do Not Do",
        list: [
          "We do not access the camera without your permission.",
          "We do not collect your location, contacts, or device identifiers for tracking.",
          "We do not sell or rent your photos or personal data.",
          "We do not serve targeted advertising based on personal data.",
        ],
      },
      {
        heading: "5. Permissions",
        paras: [
          "The App requests **camera permission**, used only to take photos for sticker generation. You can disable it anytime in your system settings; once disabled, the capture feature will not work, but viewing your saved history is unaffected.",
        ],
      },
      {
        heading: "6. Children's Privacy",
        paras: [
          "The App is not directed to children under 13. We do not knowingly collect personal information from children. If you believe a child has provided us information without parental consent, please contact us to delete it.",
        ],
      },
      {
        heading: "7. Your Rights",
        paras: [
          "Because data is stored primarily on your device, you can view, revisit, and delete your works anytime through in-app features, giving you full control over your data.",
        ],
      },
      {
        heading: "8. Policy Updates",
        paras: [
          'We may update this Privacy Policy from time to time. When we do, we will update the "Last updated" date on this page. We recommend checking this page periodically for the latest version.',
        ],
      },
      {
        heading: "9. Contact Us",
        paras: [
          "If you have any questions or requests regarding this Privacy Policy, you can reach us at:",
        ],
      },
    ],
    contactLabel: "Feedback: ",
    back: "← Back to SnapStick",
  },
};

// 把 **加粗** 标记渲染成 <strong>
function renderRich(text: string) {
  const parts = text.split(/(\*\*[^*]+\*\*)/g);
  return parts.map((part, i) =>
    part.startsWith("**") && part.endsWith("**") ? (
      <strong key={i}>{part.slice(2, -2)}</strong>
    ) : (
      <span key={i}>{part}</span>
    )
  );
}

export default function PrivacyContent() {
  const [lang, setLang] = useState<Lang>("zh");
  const t = COPY[lang];

  return (
    <main className="privacy-page" lang={lang === "zh" ? "zh-CN" : "en"}>
      <article className="privacy-content">
        <button
          type="button"
          className="privacy-lang-toggle"
          onClick={() => setLang((l) => (l === "zh" ? "en" : "zh"))}
          aria-label={lang === "zh" ? "Switch to English" : "切换到中文"}
        >
          {t.langLabel}
        </button>

        <header className="privacy-header">
          <h1>{t.title}</h1>
          <p className="privacy-subtitle">{t.subtitle}</p>
          <p className="privacy-updated">{t.updated}</p>
        </header>

        <section>
          <p>{t.intro}</p>
        </section>

        {t.sections.map((s) => (
          <section key={s.heading}>
            <h2>{s.heading}</h2>
            {s.paras?.map((p, i) => (
              <p key={i}>{renderRich(p)}</p>
            ))}
            {s.list && (
              <ul>
                {s.list.map((li, i) => (
                  <li key={i}>{renderRich(li)}</li>
                ))}
              </ul>
            )}
            {s.heading === t.sections[t.sections.length - 1].heading && (
              <p>
                {t.contactLabel}
                <a href={CONTACT_URL} target="_blank" rel="noopener noreferrer">
                  {CONTACT_LABEL_TEXT}
                </a>
              </p>
            )}
          </section>
        ))}

        <footer className="privacy-footer">
          <Link href="/">{t.back}</Link>
        </footer>
      </article>
    </main>
  );
}
