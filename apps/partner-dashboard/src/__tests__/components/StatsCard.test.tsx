import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import StatsCard from '@/components/StatsCard';

describe('StatsCard', () => {
  it('renders title and value', () => {
    render(<StatsCard title="Total Gifts" value={42} />);
    expect(screen.getByText('Total Gifts')).toBeInTheDocument();
    expect(screen.getByText('42')).toBeInTheDocument();
  });

  it('renders change with up arrow when change is positive', () => {
    render(
      <StatsCard
        title="Revenue"
        value="$1,200"
        change={{ value: '12%', positive: true }}
      />
    );
    expect(screen.getByText(/↑/)).toBeInTheDocument();
    expect(screen.getByText(/12%/)).toBeInTheDocument();
    expect(screen.getByText('vs last period')).toBeInTheDocument();
  });

  it('renders change with down arrow when change is negative', () => {
    render(
      <StatsCard
        title="Conversions"
        value="34"
        change={{ value: '5%', positive: false }}
      />
    );
    expect(screen.getByText(/↓/)).toBeInTheDocument();
    expect(screen.getByText(/5%/)).toBeInTheDocument();
  });

  it('renders without change when change prop is not provided', () => {
    render(<StatsCard title="Total Gifts" value={10} />);
    expect(screen.queryByText('vs last period')).not.toBeInTheDocument();
    expect(screen.queryByText(/↑/)).not.toBeInTheDocument();
    expect(screen.queryByText(/↓/)).not.toBeInTheDocument();
  });

  it('renders the icon when provided', () => {
    render(
      <StatsCard
        title="Commissions"
        value="$500"
        icon={<svg data-testid="test-icon" />}
      />
    );
    expect(screen.getByTestId('test-icon')).toBeInTheDocument();
  });
});
