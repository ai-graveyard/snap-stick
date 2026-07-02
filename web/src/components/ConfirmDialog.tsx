"use client";

// 通用确认弹窗（可选文本输入门槛）。对应 iOS HistoryView.swift 的 ConfirmOverlay。

import { useSettings } from "@/contexts/SettingsContext";

interface ConfirmDialogProps {
  title: string;
  message: string;
  confirmLabel: string;
  confirmDisabled?: boolean;
  danger?: boolean;
  children?: React.ReactNode;
  onCancel: () => void;
  onConfirm: () => void;
}

export default function ConfirmDialog({
  title,
  message,
  confirmLabel,
  confirmDisabled = false,
  danger = false,
  children,
  onCancel,
  onConfirm,
}: ConfirmDialogProps) {
  const { t } = useSettings();
  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/45 p-4 backdrop-blur-sm">
      <div
        role="dialog"
        aria-modal="true"
        className="w-full max-w-[18rem] rounded-2xl bg-card p-4 text-label shadow-2xl"
      >
        <h3 className="text-base font-bold">{title}</h3>
        <p className="mt-2 text-sm leading-relaxed text-label/60">{message}</p>
        {children}
        <div className="mt-4 flex items-center justify-end gap-2">
          <button onClick={onCancel} className="rounded-lg px-3 py-2 text-sm text-label/60 active:bg-chip">
            {t("取消")}
          </button>
          <button
            onClick={onConfirm}
            disabled={confirmDisabled}
            className={`rounded-lg px-3 py-2 text-sm font-semibold text-white transition-colors disabled:cursor-not-allowed disabled:bg-chip disabled:text-label/40 ${
              danger ? "bg-red-500 active:bg-red-600" : "bg-klein active:bg-klein-deep"
            }`}
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}
