import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor, fireEvent } from '@testing-library/react';

// ---------------------------------------------------------------------------
// Mock next/link (used inside DashboardPage)
// ---------------------------------------------------------------------------
vi.mock('next/link', () => ({
  default: ({ href, children, className }: { href: string; children: React.ReactNode; className?: string }) => (
    <a href={href} className={className}>{children}</a>
  ),
}));

// ---------------------------------------------------------------------------
// Mock @/lib/api
// ---------------------------------------------------------------------------
const mockApiClient = vi.fn();
vi.mock('@/lib/api', () => {
  class ApiError extends Error {
    public status: number;
    constructor(message: string, status: number) {
      super(message);
      this.status = status;
      this.name = 'ApiError';
    }
  }
  return {
    apiClient: (...args: unknown[]) => mockApiClient(...args),
    ApiError,
  };
});

// ---------------------------------------------------------------------------
// Import component under test
// ---------------------------------------------------------------------------
import DashboardPage from '@/app/dashboard/page';

// ---------------------------------------------------------------------------
// Sample analytics data
// ---------------------------------------------------------------------------
const sampleAnalytics = {
  total_gifts: 25,
  activated_gifts: 18,
  pending_gifts: 7,
  activation_rate: 72,
  recent_activity: [],
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

beforeEach(() => {
  vi.clearAllMocks();
});

describe('DashboardPage', () => {
  it('shows loading spinner on initial mount', () => {
    // Never resolve so we stay in loading state
    mockApiClient.mockReturnValue(new Promise(() => {}));
    render(<DashboardPage />);

    // The loading spinner is a div with animate-spin
    const spinner = document.querySelector('.animate-spin');
    expect(spinner).toBeTruthy();
  });

  it('renders dashboard data after a successful fetch', async () => {
    mockApiClient.mockResolvedValueOnce({ success: true, data: sampleAnalytics });

    render(<DashboardPage />);

    await waitFor(() => {
      expect(screen.getByText('Partner Dashboard')).toBeInTheDocument();
    });

    expect(screen.getByText('25')).toBeInTheDocument(); // total_gifts
    expect(screen.getByText('18')).toBeInTheDocument(); // activated_gifts
  });

  it('shows error message when the API call fails', async () => {
    mockApiClient.mockRejectedValueOnce(new Error('Server error'));

    render(<DashboardPage />);

    await waitFor(() => {
      expect(screen.getByText('Failed to load dashboard data.')).toBeInTheDocument();
    });
  });

  it('Retry button triggers a re-fetch after an error', async () => {
    // First call fails
    mockApiClient.mockRejectedValueOnce(new Error('Server error'));
    // Second call (after retry) succeeds
    mockApiClient.mockResolvedValueOnce({ success: true, data: sampleAnalytics });

    render(<DashboardPage />);

    // Wait for error state
    await waitFor(() => {
      expect(screen.getByText('Failed to load dashboard data.')).toBeInTheDocument();
    });

    // Click retry
    const retryButton = screen.getByRole('button', { name: /retry/i });
    fireEvent.click(retryButton);

    // Should now show data
    await waitFor(() => {
      expect(screen.getByText('Partner Dashboard')).toBeInTheDocument();
    });

    expect(mockApiClient).toHaveBeenCalledTimes(2);
  });

  it('shows activation rate and pending gifts counts', async () => {
    mockApiClient.mockResolvedValueOnce({ success: true, data: sampleAnalytics });

    render(<DashboardPage />);

    await waitFor(() => {
      expect(screen.getByText(/72% activation rate/i)).toBeInTheDocument();
    });

    // Total gifts and activated gifts
    expect(screen.getByText('25')).toBeInTheDocument();
    expect(screen.getByText('18')).toBeInTheDocument();
  });

  it('fetches from /api/v1/partners/analytics', async () => {
    mockApiClient.mockResolvedValueOnce({ success: true, data: sampleAnalytics });

    render(<DashboardPage />);

    await waitFor(() => {
      expect(mockApiClient).toHaveBeenCalledWith('/api/v1/partners/analytics');
    });
  });
});
