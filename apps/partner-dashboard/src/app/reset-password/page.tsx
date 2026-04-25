import { redirect } from 'next/navigation';
import Link from 'next/link';
import AuthForm from '@/components/auth-form';

/**
 * Backwards-compat entry point. The canonical reset-password URL now uses a
 * path segment (`/reset-password/<token>`) rather than a querystring so the
 * token doesn't leak into Referer headers, browser history, or
 * server access logs (audit Ch10-W019).
 *
 * If a legacy email lands on `?token=…`, we forward to the path-segment URL
 * once and let the [token] route handle it.
 */
export default function ResetPasswordIndex({
  searchParams,
}: {
  searchParams: { token?: string };
}) {
  const token = searchParams?.token;
  if (typeof token === 'string' && token.length > 0) {
    // Encode defensively — the [token] segment is enforced by the proxy's
    // SAFE_SEGMENT regex.
    redirect(`/reset-password/${encodeURIComponent(token)}`);
  }

  return (
    <AuthForm
      title="Invalid reset link"
      subtitle="This password reset link is invalid or has expired"
      footer={
        <p>
          <Link href="/forgot-password" className="text-haven-primary hover:underline">
            Request a new reset link
          </Link>
        </p>
      }
    >
      <div className="bg-haven-error/10 border border-haven-error/30 rounded-lg px-4 py-3 text-sm text-haven-error">
        The reset link is missing a required token. Please request a new password reset.
      </div>
    </AuthForm>
  );
}
