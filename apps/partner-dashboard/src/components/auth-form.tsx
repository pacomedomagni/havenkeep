'use client';

import React from 'react';

interface AuthFormProps {
  title: string;
  subtitle: string;
  children: React.ReactNode;
  footer?: React.ReactNode;
}

export default function AuthForm({ title, subtitle, children, footer }: AuthFormProps) {
  return (
    <div className="min-h-screen flex items-center justify-center bg-haven-bg px-4">
      <div className="w-full max-w-md">
        {/* Logo / Branding — matches the shield + house + checkmark used
            by sidebar.tsx, login/page.tsx, and the marketing favicon so
            every entry point lands the same brand mark. */}
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-14 h-14 mb-4">
            <svg className="w-12 h-12" viewBox="0 0 64 64" fill="none">
              <defs>
                <linearGradient id="auth-form-grad" x1="8" y1="4" x2="56" y2="63" gradientUnits="userSpaceOnUse">
                  <stop offset="0%" stopColor="#6366F1" />
                  <stop offset="100%" stopColor="#8B5CF6" />
                </linearGradient>
              </defs>
              <path d="M32 4L8 14v18c0 14.4 10.24 27.84 24 31 13.76-3.16 24-16.6 24-31V14L32 4z" fill="url(#auth-form-grad)" />
              <path d="M32 18L19 28v13h8v-8h10v8h8V28L32 18z" fill="white" opacity="0.95" />
              <path d="M27 30l4 4 8-8" stroke="#10B981" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" fill="none" />
            </svg>
          </div>
          <h1 className="text-2xl font-bold text-white">HavenKeep</h1>
          <p className="text-haven-text-tertiary text-sm mt-1">Partner Portal</p>
        </div>

        {/* Card */}
        <div className="card">
          <h2 className="text-xl font-semibold text-white mb-1">{title}</h2>
          <p className="text-haven-text-secondary text-sm mb-6">{subtitle}</p>
          {children}
        </div>

        {/* Footer */}
        {footer && (
          <div className="text-center mt-4 text-sm text-haven-text-secondary">
            {footer}
          </div>
        )}
      </div>
    </div>
  );
}
