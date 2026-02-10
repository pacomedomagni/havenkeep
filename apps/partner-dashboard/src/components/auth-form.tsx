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
        {/* Logo / Branding */}
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-14 h-14 bg-haven-primary/20 rounded-xl mb-4">
            <svg
              className="w-8 h-8 text-haven-primary"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6"
              />
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
