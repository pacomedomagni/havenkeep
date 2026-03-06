import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';

// ---------------------------------------------------------------------------
// Mock next/navigation
// ---------------------------------------------------------------------------
const mockPush = vi.fn();
vi.mock('next/navigation', () => ({
  useRouter: () => ({ push: mockPush }),
  useSearchParams: () => new URLSearchParams(),
  usePathname: () => '/dashboard',
}));

// ---------------------------------------------------------------------------
// Import component under test
// ---------------------------------------------------------------------------
import Pagination from '@/components/Pagination';

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

beforeEach(() => {
  vi.clearAllMocks();
});

describe('Pagination', () => {
  it('renders nothing when totalPages is 1', () => {
    const { container } = render(
      <Pagination page={1} totalPages={1} total={5} />
    );
    expect(container.firstChild).toBeNull();
  });

  it('renders nothing when totalPages is 0', () => {
    const { container } = render(
      <Pagination page={1} totalPages={0} total={0} />
    );
    expect(container.firstChild).toBeNull();
  });

  it('shows total results count', () => {
    render(<Pagination page={1} totalPages={3} total={42} />);
    expect(screen.getByText(/42 total results/i)).toBeInTheDocument();
  });

  it('shows current page and total pages info', () => {
    render(<Pagination page={2} totalPages={5} total={100} />);
    expect(screen.getByText(/Page 2 of 5/i)).toBeInTheDocument();
  });

  it('Previous button is disabled on the first page', () => {
    render(<Pagination page={1} totalPages={3} total={30} />);
    const prevButton = screen.getByRole('button', { name: /previous/i });
    expect(prevButton).toBeDisabled();
  });

  it('Next button is disabled on the last page', () => {
    render(<Pagination page={3} totalPages={3} total={30} />);
    const nextButton = screen.getByRole('button', { name: /next/i });
    expect(nextButton).toBeDisabled();
  });

  it('clicking Previous navigates to the previous page', () => {
    render(<Pagination page={3} totalPages={5} total={50} />);

    const prevButton = screen.getByRole('button', { name: /previous/i });
    fireEvent.click(prevButton);

    expect(mockPush).toHaveBeenCalledOnce();
    expect(mockPush).toHaveBeenCalledWith(expect.stringContaining('page=2'));
  });

  it('clicking Next navigates to the next page', () => {
    render(<Pagination page={2} totalPages={5} total={50} />);

    const nextButton = screen.getByRole('button', { name: /next/i });
    fireEvent.click(nextButton);

    expect(mockPush).toHaveBeenCalledOnce();
    expect(mockPush).toHaveBeenCalledWith(expect.stringContaining('page=3'));
  });
});
