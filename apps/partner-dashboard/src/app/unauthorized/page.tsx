export default function UnauthorizedPage() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-haven-bg">
      <div className="max-w-md w-full card text-center">
        <div className="w-16 h-16 bg-haven-error/20 rounded-full flex items-center justify-center mx-auto mb-4">
          <svg className="w-8 h-8 text-haven-error" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
          </svg>
        </div>
        <h1 className="text-2xl font-bold text-white mb-2">Access Denied</h1>
        <p className="text-haven-text-secondary mb-6">
          You do not have admin privileges to access this dashboard.
        </p>
        <a
          href="/login"
          className="btn-primary inline-block py-2 px-6"
        >
          Back to Login
        </a>
      </div>
    </div>
  )
}
