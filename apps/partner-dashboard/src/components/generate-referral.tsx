'use client';

import { useState } from 'react';
import { ClipboardDocumentIcon, CheckIcon, XMarkIcon } from '@heroicons/react/24/outline';

interface GenerateReferralProps {
  isOpen: boolean;
  onClose: () => void;
}

export default function GenerateReferral({ isOpen, onClose }: GenerateReferralProps) {
  const [code, setCode] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [loading, setLoading] = useState(false);

  async function generateCode() {
    setLoading(true);
    // Simulate API call
    await new Promise((resolve) => setTimeout(resolve, 800));
    const newCode = `HK-${Math.random().toString(36).substring(2, 6).toUpperCase()}-${Math.random()
      .toString(36)
      .substring(2, 6)
      .toUpperCase()}`;
    setCode(newCode);
    setLoading(false);
  }

  async function copyToClipboard(text: string) {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Fallback
    }
  }

  function handleClose() {
    setCode(null);
    setCopied(false);
    onClose();
  }

  if (!isOpen) return null;

  const shareableLink = code ? `https://havenkeep.app/referral/${code}` : '';

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 px-4">
      <div className="bg-haven-surface border border-haven-border rounded-xl w-full max-w-md p-6">
        {/* Header */}
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-lg font-semibold text-white">Generate Referral Code</h2>
          <button
            onClick={handleClose}
            className="text-haven-text-tertiary hover:text-white transition-colors"
          >
            <XMarkIcon className="w-5 h-5" />
          </button>
        </div>

        {!code ? (
          <div className="text-center">
            <p className="text-haven-text-secondary text-sm mb-6">
              Generate a unique referral code to share with your clients. You&apos;ll earn a
              commission for every user who signs up with your code.
            </p>
            <button onClick={generateCode} disabled={loading} className="btn-primary w-full">
              {loading ? (
                <span className="inline-flex items-center gap-2">
                  <svg className="animate-spin h-4 w-4" viewBox="0 0 24 24">
                    <circle
                      className="opacity-25"
                      cx="12"
                      cy="12"
                      r="10"
                      stroke="currentColor"
                      strokeWidth="4"
                      fill="none"
                    />
                    <path
                      className="opacity-75"
                      fill="currentColor"
                      d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
                    />
                  </svg>
                  Generating...
                </span>
              ) : (
                'Generate Code'
              )}
            </button>
          </div>
        ) : (
          <div className="space-y-4">
            {/* Generated code */}
            <div>
              <label className="block text-xs font-medium text-haven-text-tertiary uppercase tracking-wider mb-2">
                Your Referral Code
              </label>
              <div className="flex items-center gap-2">
                <div className="flex-1 bg-haven-elevated border border-haven-border rounded-lg px-4 py-3 font-mono text-lg text-haven-primary text-center">
                  {code}
                </div>
                <button
                  onClick={() => copyToClipboard(code)}
                  className="p-3 bg-haven-elevated border border-haven-border rounded-lg hover:bg-haven-primary/15 transition-colors"
                  title="Copy code"
                >
                  {copied ? (
                    <CheckIcon className="w-5 h-5 text-haven-active" />
                  ) : (
                    <ClipboardDocumentIcon className="w-5 h-5 text-haven-text-secondary" />
                  )}
                </button>
              </div>
            </div>

            {/* Shareable link */}
            <div>
              <label className="block text-xs font-medium text-haven-text-tertiary uppercase tracking-wider mb-2">
                Shareable Link
              </label>
              <div className="flex items-center gap-2">
                <input
                  type="text"
                  value={shareableLink}
                  readOnly
                  className="input-field text-sm font-mono"
                />
                <button
                  onClick={() => copyToClipboard(shareableLink)}
                  className="p-3 bg-haven-elevated border border-haven-border rounded-lg hover:bg-haven-primary/15 transition-colors shrink-0"
                  title="Copy link"
                >
                  <ClipboardDocumentIcon className="w-5 h-5 text-haven-text-secondary" />
                </button>
              </div>
            </div>

            <button onClick={handleClose} className="btn-secondary w-full mt-2">
              Done
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
