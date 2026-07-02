import type { Metadata } from "next";
import PrivacyContent from "./PrivacyContent";

export const metadata: Metadata = {
  title: "隐私政策 · 拍立贴 SnapStick",
  description:
    "拍立贴（SnapStick）隐私政策：说明我们如何处理摄像头、照片与生成的贴纸数据。",
};

export default function PrivacyPolicyPage() {
  return <PrivacyContent />;
}
